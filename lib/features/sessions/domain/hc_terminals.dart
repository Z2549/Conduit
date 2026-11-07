import 'dart:convert';

import 'package:conduit/features/agent_attention/data/remote_tool_command.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';

/// One herdr-core terminal as `hc ls --json` reports it (CON-100000).
///
/// Checked against hc 0.1.16, whose list is
/// `{"hidden_finished": 0, "terminals": [{"address": "t2", "agent": "cat",
/// "cwd": "/root/app", "name": "api", "state": "live", "turn": 0}]}`.
/// `status` is the program's own OSC 7501 word (`idle`, `working`, `done`,
/// `blocked`, `error`) and is left out while a program never reported one,
/// so plain programs have none.
class HcTerminalInfo {
  const HcTerminalInfo({
    required this.address,
    this.name = '',
    this.agent = '',
    this.cwd = '',
    this.live = true,
    this.status = '',
    this.turn = 0,
    this.where = '',
    this.title = '',
    this.spaceId = '',
  });

  /// `t7` on its own machine, `machine/t7` for one hc reaches elsewhere:
  /// what every `hc` command takes.
  final String address;

  /// The name given at `hc run --name`; empty when none.
  final String name;

  /// What runs in it (`claude`, `codex`, `bash`).
  final String agent;
  final String cwd;

  /// `state: live`; false once the program has finished.
  final bool live;

  /// The program's status word, lower case; empty when it never said.
  final String status;

  /// Goes up each time the status leaves `working`.
  final int turn;

  /// Where the Herdr app shows it: `<space> / <tab>`; empty when no app
  /// window has it.
  final String where;

  /// The terminal's own title (Claude Code names it after the task, the
  /// way the Herdr app's sidebar shows it); empty when `hc ls` was the
  /// source, which leaves it out (CON-135).
  final String title;

  /// The id of the Herdr app space it sits in (its `herdr.space` label):
  /// tells apart spaces that share a name ("Projects", "~"); empty when
  /// unknown.
  final String spaceId;

  /// The name an agent row shows, as the Herdr app's sidebar does: its
  /// [title] without the spinner or status glyph a program puts in front,
  /// else [displayLabel]. A shell's `user@host:dir` title is not a name.
  String get agentTitle {
    final clean = title.replaceFirst(_titleGlyphs, '').trim();
    if (clean.isEmpty || _promptTitle.hasMatch(clean)) return displayLabel;
    return clean;
  }

  static final _titleGlyphs = RegExp(
    r'^[\u2800-\u28FF\u2700-\u27BF\u2600-\u26FF\u2022\u00B7*\s]+',
  );
  static final _promptTitle = RegExp(r'^[^\s@]+@[^\s:]+:');

  /// The Herdr app space it sits in (the part of [where] before ` / `).
  String get space {
    final at = where.lastIndexOf(' / ');
    return (at == -1 ? where : where.substring(0, at)).trim();
  }

  /// The machine part of [address]; empty for a terminal on this machine.
  String get machine {
    final slash = address.lastIndexOf('/');
    return slash == -1 ? '' : address.substring(0, slash);
  }

  /// The folder [cwd] ends in; empty without one.
  String get folder =>
      cwd.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '';

  /// The name to show, never the bare address when anything better exists:
  /// its name, else where it is in the app ("Calendar", or "Calendar / 2"
  /// past the first tab), else "agent in folder", else the address.
  String get displayLabel {
    if (name.isNotEmpty) return name;
    if (where.isNotEmpty) {
      return where.endsWith(' / 1') ? space : where.trim();
    }
    if (agent.isNotEmpty && folder.isNotEmpty) return '$agent in $folder';
    if (agent.isNotEmpty) return agent;
    return address;
  }

  @override
  bool operator ==(Object other) =>
      other is HcTerminalInfo &&
      other.address == address &&
      other.name == name &&
      other.agent == agent &&
      other.cwd == cwd &&
      other.live == live &&
      other.status == status &&
      other.turn == turn &&
      other.where == where &&
      other.title == title &&
      other.spaceId == spaceId;

  @override
  int get hashCode => Object.hash(
    address,
    name,
    agent,
    cwd,
    live,
    status,
    turn,
    where,
    title,
    spaceId,
  );

  @override
  String toString() => 'HcTerminalInfo($address)';
}

/// The phone's workspace id for the Herdr app space [key]: `wHc` plus an
/// FNV-1a hash of the space id (`sp…`). The board's workspaces and the
/// Herdr app's project members (`name#sp…`) both go through it, so a
/// member finds its own space (CON-135). With [named] the key is the
/// space's name because hc gave no space id (an hc without
/// `terminal.list`): the id starts `wHcn`, which [ProjectKeys.same]
/// matches by name.
String hcSpaceWorkspaceId(String key, {bool named = false}) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return '${named ? hcNamedWorkspacePrefix : 'wHc'}${hash.toRadixString(16)}';
}

/// See [hcSpaceWorkspaceId].
const hcNamedWorkspacePrefix = 'wHcn';

/// `hc` commands, wrapped for a non-interactive SSH shell like the herdr
/// ones (see [remoteToolCommand]). Every command was run against hc 0.1.16.
abstract final class HcCommands {
  static String _hc(String args) => remoteToolCommand('hc', args);

  /// The home board's list (the only caller: ~6x the bytes of [ls], so the
  /// background monitors keep [ls]). The live terminals of every machine
  /// hc reaches: `terminal.list` over
  /// `hc connect`, which carries each terminal's title and labels (CON-135),
  /// else `hc ls --json` (no titles) when that answer is missing, so an hc
  /// without the call, or a missing hc, reads as before.
  static final list = () {
    final request = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'terminal.list',
      'params': <String, Object?>{},
    });
    final inner =
        'PATH="${remoteToolExtraPathDirs.join(':')}:\$PATH"; '
        'out=\$(printf \'%s\\n\' ${shellQuoteArgument(request)} '
        '| hc connect 2>/dev/null); '
        'case "\$out" in *\'"terminals"\'*) printf \'%s\\n\' "\$out";; '
        '*) exec hc ls --json;; esac';
    return 'sh -c ${shellQuoteArgument(inner)}';
  }();

  /// `hc ls --json`: live terminals without titles or space ids, and the
  /// machines hc reaches (`machines`). What the agent monitors and the
  /// connect picker poll.
  static final ls = _hc('ls --json');

  /// `hc read <t> --lines <n>`: the screen plus [lines] of history, as text.
  static String read(String address, {int lines = 200}) =>
      _hc('read --lines $lines -- ${shellQuoteArgument(address)}');

  /// `hc send <t> <text>`: pastes [text] and presses Enter once nobody has
  /// typed for about three seconds. hc refuses a blocked program (exit 9);
  /// the phone never passes `--force`, so a permission prompt is answered
  /// in the terminal itself. `--` ends hc's options, so text such as `-h`
  /// or `- fix tests` is typed instead of read as a flag.
  static String send(String address, String text) =>
      _hc('send -- ${shellQuoteArgument(address)} ${shellQuoteArgument(text)}');

  /// Answers question [n] of card [id] on [address]'s agent and sends it
  /// there, as the Work panel's Send does: `cards stage` then `cards send`
  /// on the machine that keeps the agent's cards (its own, through
  /// `hc exec --on` when it is not this one).
  static String answerCard(String address, String id, int n, String answer) {
    final slash = address.lastIndexOf('/');
    final machine = slash == -1 ? '' : address.substring(0, slash);
    final terminal = address.substring(slash + 1);
    String cards(List<String> args) {
      final argv = args.map(shellQuoteArgument).join(' ');
      return machine.isEmpty
          ? remoteToolCommand('cards', argv)
          : _hc('exec --on ${shellQuoteArgument(machine)} cards $argv');
    }

    final both =
        '${cards(['stage', terminal, id, '$n', answer])} && '
        '${cards(['send', terminal])}';
    return 'sh -c ${shellQuoteArgument(both)}';
  }

  /// `hc keys <t> <keys...>`: named keys (`enter`, `esc`, `up`, `ctrl+c`).
  static String keys(String address, List<String> keys) => _hc(
    'keys -- ${shellQuoteArgument(address)} '
    '${keys.map(shellQuoteArgument).join(' ')}',
  );

  /// `doc.get` for [names] over `hc connect` (JSON-RPC lines on stdin and
  /// stdout), one request per name with ids 1, 2, ... in order, then the
  /// same names again on each machine of [on] (ids go on counting);
  /// [skipLocal] leaves out this machine's round. A document nobody wrote
  /// comes back as `{"value": null, "version": 0}`.
  static String docGet(
    List<String> names, {
    List<String> on = const [],
    bool skipLocal = false,
  }) {
    final requests = [
      for (final (round, machine) in [if (!skipLocal) null, ...on].indexed)
        for (final (index, name) in names.indexed)
          jsonEncode({
            'jsonrpc': '2.0',
            'id': round * names.length + index + 1,
            'method': 'doc.get',
            'params': {'name': name, 'on': ?machine},
          }),
    ];
    final inner =
        'PATH="${remoteToolExtraPathDirs.join(':')}:\$PATH"; '
        "printf '%s\\n' ${requests.map(shellQuoteArgument).join(' ')} "
        '| hc connect';
    return 'sh -c ${shellQuoteArgument(inner)}';
  }

  /// `command -v hc` and `command -v herdr` with the same PATH as the
  /// other commands: prints `hc` and/or `herdr` for what is installed.
  static final probe = () {
    final inner =
        'PATH="${remoteToolExtraPathDirs.join(':')}:\$PATH"; '
        'for t in hc herdr; do command -v "\$t" >/dev/null && echo "\$t"; '
        'done; true';
    return 'sh -c ${shellQuoteArgument(inner)}';
  }();

  /// [HostBackend.suggest] from [probe]'s output.
  static HostBackend suggestFromProbe(String stdout) {
    final found = const LineSplitter().convert(stdout).map((l) => l.trim());
    return HostBackend.suggest(
      hcInstalled: found.contains('hc'),
      herdrInstalled: found.contains('herdr'),
    );
  }
}

/// Parsing for `hc` output, separate from running it so the picker and the
/// agent monitor are tested against captured output.
abstract final class HcListing {
  /// What `hc ls --json` printed, as a listing: not installed, the core not
  /// reachable, or the terminals.
  static RemoteListing<HcTerminalInfo> interpret(AgentCommandResult result) {
    final stderr = result.stderr.trim();
    if (result.exitCode == 127 ||
        stderr.contains('command not found') ||
        stderr.contains('hc: not found')) {
      return const RemoteListingNotInstalled();
    }
    if (result.exitCode != null && result.exitCode != 0) {
      return RemoteListingFailed(errorMessage(stderr, result.exitCode));
    }
    try {
      return RemoteListingAvailable(parseTerminals(result.stdout));
    } on FormatException catch (error) {
      return RemoteListingFailed(error.message);
    }
  }

  /// Parses `hc ls --json` (or a bare array of terminals, or the
  /// `terminal.list` result of `hc connect`). Entries without an address
  /// are skipped; finished terminals are kept with `live: false`. Throws
  /// [FormatException] when the output is not JSON.
  static List<HcTerminalInfo> parseTerminals(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      // `hc connect` may print more than the one answer: take that line.
      decoded = _answerLine(trimmed);
      if (decoded == null) {
        throw const FormatException('hc returned output that is not JSON.');
      }
    }
    if (decoded is Map && decoded['result'] is Map) {
      decoded = decoded['result'];
    }
    final items = switch (decoded) {
      List() => decoded,
      Map() when decoded['terminals'] is List => decoded['terminals'] as List,
      Map() when decoded['error'] is Map => throw FormatException(
        _string(decoded['error'] as Map, const ['message']) ??
            'hc reported an error.',
      ),
      _ => throw const FormatException(
        'hc returned JSON in an unexpected shape.',
      ),
    };
    return [
      for (final item in items)
        if (item is Map && _string(item, const ['address']) != null)
          HcTerminalInfo(
            address: _string(item, const ['address'])!,
            name: _string(item, const ['name']) ?? '',
            agent:
                _string(item, const ['agent']) ??
                _statusApp(item['status']) ??
                _foregroundName(item['foreground']) ??
                '',
            cwd: _string(item, const ['cwd']) ?? '',
            live: (_string(item, const ['state']) ?? 'live') == 'live',
            status: _status(item['status']),
            turn: item['turn'] is int ? item['turn'] as int : 0,
            where:
                _string(item, const ['where']) ?? _label(item, 'where') ?? '',
            title: _string(item, const ['title']) ?? '',
            spaceId: _label(item, 'herdr.space') ?? '',
          ),
    ];
  }

  /// The status word: hc's list prints it as a string, `hc get` and the
  /// API as a record whose `state` is the word.
  static String _status(Object? raw) {
    final word = switch (raw) {
      String() => raw,
      Map() => raw['state'] is String ? raw['state'] as String : '',
      _ => '',
    };
    return word.trim().toLowerCase();
  }

  /// The program the status record names (`claude-code`), as `hc ls`
  /// prints it under `agent`.
  static String? _statusApp(Object? status) =>
      status is Map ? _string(status, const ['app']) : null;

  /// Label [key] of a terminal record (`terminal.list`, `hc get`).
  static String? _label(Map<Object?, Object?> item, String key) =>
      item['labels'] is Map ? _string(item['labels'] as Map, [key]) : null;

  /// The first line of [raw] that is a JSON answer carrying terminals.
  static Object? _answerLine(String raw) {
    for (final line in const LineSplitter().convert(raw)) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map &&
            decoded['result'] is Map &&
            (decoded['result'] as Map)['terminals'] is List) {
          return decoded;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static String? _foregroundName(Object? foreground) =>
      foreground is Map ? _string(foreground, const ['name']) : null;

  /// One line for a failed `hc` command: hc prints
  /// `{"error": {"kind", "message", "hint"}}` on stderr; the kinds a phone
  /// user can act on get their own wording.
  static String errorMessage(String stderr, int? exitCode) {
    Map<Object?, Object?>? error;
    try {
      final decoded = jsonDecode(stderr);
      if (decoded is Map && decoded['error'] is Map) {
        error = decoded['error'] as Map;
      }
    } catch (_) {
      // Plain text: shown as it is below.
    }
    final kind = error == null ? null : _string(error, const ['kind']);
    if (exitCode == 9 || kind == 'blocked') {
      return 'It is waiting on a decision: open the terminal to answer it.';
    }
    if (exitCode == 3 || kind == 'not_found') {
      return 'That terminal is gone.';
    }
    if (exitCode == 11 || kind == 'finished') {
      return 'That terminal has finished.';
    }
    final message = error == null ? null : _string(error, const ['message']);
    if (message != null) return message;
    if (stderr.isNotEmpty) {
      return stderr.length > 200 ? stderr.substring(0, 200) : stderr;
    }
    return 'hc exited with $exitCode.';
  }

  /// The `value` of each `doc.get` answer in `hc connect` output, by
  /// request id. Lines that are not answers (or are errors) are left out,
  /// so a missing or unreadable document reads as absent.
  static Map<int, Object?> parseDocAnswers(String raw) {
    final values = <int, Object?>{};
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(line);
      } catch (_) {
        continue;
      }
      if (decoded is! Map || decoded['id'] is! int) continue;
      final result = decoded['result'];
      if (result is Map) {
        values[decoded['id'] as int] = result['value'];
      }
    }
    return values;
  }

  static String? _string(Map<Object?, Object?> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}

/// The Herdr actions the phone offers, and which a backend can do.
enum MultiplexerAction {
  list,
  read,
  send,
  keys,
  attach,

  /// Focus a pane (or agent) in the desktop UI.
  focusPane,
  splitPane,
  zoomPane,
  newTab,
  newWorkspace,

  /// Herdr's prefix keymap inside the attached TUI.
  prefixKeys;

  String get label => switch (this) {
    MultiplexerAction.list => 'List terminals',
    MultiplexerAction.read => 'Read',
    MultiplexerAction.send => 'Send',
    MultiplexerAction.keys => 'Keys',
    MultiplexerAction.attach => 'Open',
    MultiplexerAction.focusPane => 'Focus in the app',
    MultiplexerAction.splitPane => 'Split',
    MultiplexerAction.zoomPane => 'Zoom',
    MultiplexerAction.newTab => 'New tab',
    MultiplexerAction.newWorkspace => 'New workspace',
    MultiplexerAction.prefixKeys => 'Herdr keys',
  };
}

/// Why [action] is not available on [backend], or null when it is.
///
/// The herdr and sheprd backends drive the herdr CLI, which has all of
/// them. hc has no command for the desktop app's panes, tabs and spaces
/// (the app keeps them in its own private document), and attaching shows
/// one terminal with no TUI around it, so those are left out on the phone
/// instead of being imitated.
String? unsupportedReason(HostBackend backend, MultiplexerAction action) {
  if (backend != HostBackend.hc) return null;
  return switch (action) {
    MultiplexerAction.list ||
    MultiplexerAction.read ||
    MultiplexerAction.send ||
    MultiplexerAction.keys ||
    MultiplexerAction.attach => null,
    MultiplexerAction.focusPane =>
      'hc cannot move the Herdr app\'s focus; open the terminal here instead.',
    MultiplexerAction.splitPane || MultiplexerAction.zoomPane =>
      'Panes are the Herdr app\'s layout; hc has '
          'no command for them.',
    MultiplexerAction.newTab || MultiplexerAction.newWorkspace =>
      'Spaces and tabs live in the Herdr app '
          'only; hc has no command for them.',
    MultiplexerAction.prefixKeys =>
      'An hc terminal is attached on its own, without a TUI around it.',
  };
}

/// The actions [backend] cannot do, each with its reason, in a fixed order.
List<(MultiplexerAction, String)> unsupportedActions(HostBackend backend) => [
  for (final action in MultiplexerAction.values)
    if (unsupportedReason(backend, action) case final reason?) (action, reason),
];
