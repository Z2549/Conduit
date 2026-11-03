import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:flutter/foundation.dart';

/// The two herdr-core documents sheprd's Herdr app mods share
/// (docs/herdr-core-contract.md, contract v1), read on the hc backend
/// (CON-100000) instead of sheprd's `view.json`. The phone only reads them.
abstract final class HcDocuments {
  static const view = 'sheprd-view';
  static const cards = 'sheprd-cards';
}

/// Both documents as one machine had them; empty when absent.
@immutable
class HcSheprdDocuments {
  const HcSheprdDocuments({this.view, this.cards = const {}});

  /// Null without a (v1) `sheprd-view`.
  final HcSheprdView? view;

  /// Open cards by terminal address.
  final Map<String, List<HcCard>> cards;
}

/// One project of `sheprd-view`: sheprd's `[[group]]` from `sidebar.toml`.
@immutable
class HcProject {
  const HcProject({
    required this.name,
    this.short = '',
    this.pinned = false,
    this.collapsed = false,
    this.members = const [],
    this.match = const [],
    this.note,
  });

  final String name;

  /// The two-letter rail tag; empty when sheprd set none.
  final String short;
  final bool pinned;
  final bool collapsed;

  /// `machine/<space name>`, `local/...` for the hub.
  final List<String> members;

  /// Case-insensitive substrings of a space's name or folder.
  final List<String> match;
  final String? note;

  static HcProject? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final short = json['short'];
    final note = json['note'];
    return HcProject(
      name: name.trim(),
      short: short is String ? short.trim() : '',
      pinned: json['pinned'] == true,
      collapsed: json['collapsed'] == true,
      members: _strings(json['members']),
      match: _strings(json['match']),
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
    );
  }
}

/// sheprd's view filter.
enum HcViewFilter {
  needsYou,
  working,
  marked,
  all;

  static HcViewFilter parse(Object? raw) => switch (raw) {
    'needs-you' => HcViewFilter.needsYou,
    'working' => HcViewFilter.working,
    'marked' => HcViewFilter.marked,
    _ => HcViewFilter.all,
  };
}

/// Where a document's keys point from the phone's side.
///
/// The documents name machines as the machine that holds them sees them:
/// a bare `t7` or `local/t7` is that machine's own, `omarchy/t7` one it
/// reaches. Read from another machine (the Herdr app's hub, with `on`), the
/// phone's host shows up under the hub's name for it, which the phone does
/// not know: a machine name that is neither the hub nor one the phone
/// reaches is taken for the phone's host.
@immutable
class HcKeyScope {
  const HcKeyScope({this.hub = '', this.machines = const {}});

  /// The machine the document came from, as the phone names it; empty for
  /// the phone's host.
  final String hub;

  /// The machines the phone's host reaches (`hc ls` address prefixes).
  final Set<String> machines;

  /// The phone-side machine for a key's machine part (null for none).
  String machineOf(String? prefix) {
    if (prefix == null || prefix == 'local') return hub;
    if (prefix == hub || machines.contains(prefix)) return prefix;
    return hub.isEmpty ? prefix : '';
  }

  /// [key] split into its phone-side machine and the rest.
  (String, String) split(String key) {
    final slash = key.indexOf('/');
    if (slash == -1) return (machineOf(null), key);
    return (machineOf(key.substring(0, slash)), key.substring(slash + 1));
  }

  /// [key] as an address `hc ls` on the phone's host gives.
  String address(String key) {
    final (machine, bare) = split(key);
    return machine.isEmpty ? bare : '$machine/$bare';
  }
}

/// The `sheprd-view` document: projects, hidden spaces and marks.
@immutable
class HcSheprdView {
  const HcSheprdView({
    this.projects = const [],
    this.hidden = const {},
    this.filter = HcViewFilter.all,
    this.activeOnly = false,
    this.otherCollapsed = false,
    this.unread = const {},
    this.kept = const {},
    this.dismissed = const {},
    this.marked = const {},
    this.compact = false,
    this.scope = const HcKeyScope(),
  });

  final List<HcProject> projects;
  final Set<String> hidden;
  final HcViewFilter filter;
  final bool activeOnly;
  final bool otherCollapsed;

  /// Mark keys as sheprd writes them: `machine/t7`.
  final Set<String> unread;
  final Set<String> kept;

  /// `machine/t7@<seq>`: lapses when the terminal's turn moves on.
  final Set<String> dismissed;

  /// The user's own flag on an agent (★ in the sidebar).
  final Set<String> marked;

  /// `density: compact`: one line per agent.
  final bool compact;

  /// How the keys above map to the phone's addresses.
  final HcKeyScope scope;

  /// This view read from [scope]'s hub.
  HcSheprdView scoped(HcKeyScope scope) => HcSheprdView(
    projects: projects,
    hidden: hidden,
    filter: filter,
    activeOnly: activeOnly,
    otherCollapsed: otherCollapsed,
    unread: unread,
    kept: kept,
    dismissed: dismissed,
    marked: marked,
    compact: compact,
    scope: scope,
  );

  /// Null when [json] is not a v1 view (absent, never written, or another
  /// shape), so callers fall back to an ungrouped list.
  static HcSheprdView? fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return null;
    final marks = json['marks'] is Map
        ? json['marks'] as Map<Object?, Object?>
        : const <Object?, Object?>{};
    return HcSheprdView(
      projects: [
        if (json['projects'] case final List<Object?> projects)
          for (final raw in projects) ?HcProject.fromJson(raw),
      ],
      hidden: _strings(json['hidden']).toSet(),
      filter: HcViewFilter.parse(json['filter']),
      activeOnly: json['active_only'] == true,
      otherCollapsed: json['other_collapsed'] == true,
      unread: _strings(marks['unread']).toSet(),
      kept: _strings(marks['kept']).toSet(),
      dismissed: _strings(marks['dismissed']).toSet(),
      marked: _strings(marks['marked']).toSet(),
      compact: json['density'] == 'compact',
    );
  }

  /// The project [terminal] belongs to, or null for Other.
  ///
  /// sheprd assigns spaces: members win over match rules, then the first
  /// project whose rule matches takes it. The phone does not know which
  /// space of the Herdr app a terminal sits in (the app keeps that in its
  /// own document), so the terminal's folder stands in for the space name:
  /// a member `machine/<folder>` or a rule matching the folder, the cwd or
  /// the terminal's name.
  HcProject? projectOf(HcTerminalInfo terminal) {
    for (final project in projects) {
      if (project.members.any((member) => _isSpace(member, terminal))) {
        return project;
      }
    }
    final haystacks = [
      terminal.folder,
      terminal.cwd,
      terminal.name,
    ].where((text) => text.isNotEmpty).map((text) => text.toLowerCase());
    for (final project in projects) {
      for (final rule in project.match) {
        final needle = rule.toLowerCase();
        if (needle.isNotEmpty && haystacks.any((h) => h.contains(needle))) {
          return project;
        }
      }
    }
    return null;
  }

  /// Whether the sidebar hides [terminal]'s space (its folder standing in,
  /// as in [projectOf]).
  bool isHidden(HcTerminalInfo terminal) =>
      hidden.any((key) => _isSpace(key, terminal));

  /// Whether the user marked [terminal] (★).
  bool isMarked(HcTerminalInfo terminal) =>
      marked.any((key) => _isTerminal(key, terminal));

  /// Whether sheprd counts [terminal] as needing you: unread, or blocked or
  /// done and not dismissed at its current turn.
  bool needsYou(HcTerminalInfo terminal) {
    if (unread.any((key) => _isTerminal(key, terminal))) return true;
    if (terminal.status != 'blocked' && terminal.status != 'done') {
      return false;
    }
    return !dismissed.any(
      (key) =>
          key.endsWith('@${terminal.turn}') &&
          _isTerminal(key.substring(0, key.lastIndexOf('@')), terminal),
    );
  }

  /// A mark key (`t7`, `local/t7`, `dev/t7`) names [terminal].
  bool _isTerminal(String key, HcTerminalInfo terminal) =>
      scope.address(key) == terminal.address;

  /// A space key (`machine/<space name>`) names [terminal]'s folder.
  bool _isSpace(String key, HcTerminalInfo terminal) {
    if (!key.contains('/')) return false;
    final (machine, space) = scope.split(key);
    return machine == terminal.machine &&
        space.toLowerCase() == terminal.folder.toLowerCase();
  }
}

/// One question on a card.
@immutable
class HcCardQuestion {
  const HcCardQuestion({
    required this.number,
    required this.text,
    this.options = const [],
    this.state = 'open',
  });

  final int number;
  final String text;
  final List<String> options;

  /// `open`, `staged`, `sending`, `sent` or `dismissed`.
  final String state;

  /// Not answered yet as far as the agent knows: `open`, `staged` (an
  /// answer chosen) or `sending` (a `cards send` has claimed it; a failed
  /// send puts it back to `staged`). The phone only reads these states and
  /// never writes them.
  bool get isOpen => const {'open', 'staged', 'sending'}.contains(state);

  /// A `cards send` is delivering its answer right now.
  bool get isSending => state == 'sending';
}

/// One card of `sheprd-cards`, the agents' card ledger.
@immutable
class HcCard {
  const HcCard({
    required this.id,
    required this.terminal,
    this.title = '',
    this.status = '',
    this.summary = '',
    this.questions = const [],
    this.done = false,
  });

  final String id;

  /// The address of the terminal whose agent keeps the card (`t7`).
  final String terminal;
  final String title;
  final String status;
  final String summary;
  final List<HcCardQuestion> questions;
  final bool done;

  int get openQuestions => questions.where((q) => q.isOpen).length;

  /// "SHE-12 Stripe checkout".
  String get headline => title.isEmpty ? id : '$id $title';
}

/// The `sheprd-cards` document, cards by the terminal that keeps them.
abstract final class HcCards {
  /// Cards that are neither dismissed nor done, by terminal address. An
  /// absent or unreadable document gives no cards.
  /// Terminal addresses are the ones the phone's host uses, translated
  /// through [scope] when the document came from another machine.
  static Map<String, List<HcCard>> byTerminal(
    Object? json, {
    HcKeyScope scope = const HcKeyScope(),
  }) {
    if (json is! Map || json['v'] != 1 || json['cards'] is! Map) {
      return const {};
    }
    final out = <String, List<HcCard>>{};
    for (final raw in (json['cards'] as Map).values) {
      if (raw is! Map || raw['dismissed'] == true || raw['done'] == true) {
        continue;
      }
      final id = raw['id'];
      final key = raw['terminal'];
      if (id is! String || key is! String || id.isEmpty) continue;
      final terminal = scope.address(key);
      out
          .putIfAbsent(terminal, () => [])
          .add(
            HcCard(
              id: id,
              terminal: terminal,
              title: _string(raw['title']),
              status: _string(raw['status']),
              summary: _string(raw['summary']),
              questions: [
                if (raw['questions'] case final List<Object?> questions)
                  for (final q in questions)
                    if (q is Map && q['n'] is int && q['text'] is String)
                      HcCardQuestion(
                        number: q['n'] as int,
                        text: q['text'] as String,
                        options: _strings(q['options']),
                        state: _string(q['state']).isEmpty
                            ? 'open'
                            : _string(q['state']),
                      ),
              ],
            ),
          );
    }
    return out;
  }

  static String _string(Object? raw) => raw is String ? raw.trim() : '';
}

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
];
