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

  /// The machine part of [address]; empty for a terminal on this machine.
  String get machine {
    final slash = address.lastIndexOf('/');
    return slash == -1 ? '' : address.substring(0, slash);
  }

  /// The folder [cwd] ends in; empty without one.
  String get folder =>
      cwd.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '';

  /// The name to show, never the bare address when anything better exists:
  /// its name, else "agent in folder", else the address.
  String get displayLabel {
    if (name.isNotEmpty) return name;
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
      other.turn == turn;

  @override
  int get hashCode =>
      Object.hash(address, name, agent, cwd, live, status, turn);

  @override
  String toString() => 'HcTerminalInfo($address)';
}

/// `hc` commands, wrapped for a non-interactive SSH shell like the herdr
/// ones (see [remoteToolCommand]). Every command was run against hc 0.1.16.
abstract final class HcCommands {
  static String _hc(String args) => remoteToolCommand('hc', args);

  /// `hc ls --json`: live terminals.
  static final list = _hc('ls --json');

  /// `hc read <t> --lines <n>`: the screen plus [lines] of history, as text.
  static String read(String address, {int lines = 200}) =>
      _hc('read ${shellQuoteArgument(address)} --lines $lines');

  /// `hc send <t> <text>`: pastes [text] and presses Enter once nobody has
  /// typed for about three seconds. hc refuses a blocked program (exit 9);
  /// the phone never passes `--force`, so a permission prompt is answered
  /// in the terminal itself.
  static String send(String address, String text) => _hc(
    'send ${shellQuoteArgument(address)} ${shellQuoteArgument(text)}',
  );

  /// `hc keys <t> <keys...>`: named keys (`enter`, `esc`, `up`, `ctrl+c`).
  static String keys(String address, List<String> keys) => _hc(
    'keys ${shellQuoteArgument(address)} '
    '${keys.map(shellQuoteArgument).join(' ')}',
  );

  /// `hc attach <t>`, typed into the session's shell: puts the phone's
  /// terminal on it. ctrl+\ detaches back to that shell, like the herdr
  /// and tmux attaches, which do not `exec` either.
  static String attach(String address) =>
      'hc attach ${shellQuoteArgument(address)}';

  /// `doc.get` for [names] over `hc connect` (JSON-RPC lines on stdin and
  /// stdout), one request per name with ids 1, 2, ... in order. A document
  /// nobody wrote comes back as `{"value": null, "version": 0}`.
  static String docGet(List<String> names) {
    final requests = [
      for (final (index, name) in names.indexed)
        jsonEncode({
          'jsonrpc': '2.0',
          'id': index + 1,
          'method': 'doc.get',
          'params': {'name': name},
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
      throw const FormatException('hc returned output that is not JSON.');
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
                _foregroundName(item['foreground']) ??
                '',
            cwd: _string(item, const ['cwd']) ?? '',
            live: (_string(item, const ['state']) ?? 'live') == 'live',
            status: _status(item['status']),
            turn: item['turn'] is int ? item['turn'] as int : 0,
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
    MultiplexerAction.splitPane ||
    MultiplexerAction.zoomPane => 'Panes are the Herdr app\'s layout; hc has '
        'no command for them.',
    MultiplexerAction.newTab ||
    MultiplexerAction.newWorkspace => 'Spaces and tabs live in the Herdr app '
        'only; hc has no command for them.',
    MultiplexerAction.prefixKeys =>
      'An hc terminal is attached on its own, without a TUI around it.',
  };
}

/// The actions [backend] cannot do, each with its reason, in a fixed order.
List<(MultiplexerAction, String)> unsupportedActions(HostBackend backend) => [
  for (final action in MultiplexerAction.values)
    if (unsupportedReason(backend, action) case final reason?)
      (action, reason),
];
