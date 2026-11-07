import 'dart:async';
import 'dart:convert';

import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/remote_tool_command.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/desktop_shell/domain/hc_documents.dart';
import 'package:conduit/features/desktop_shell/domain/project_layout.dart';
import 'package:conduit/features/desktop_shell/domain/project_tree.dart';
import 'package:conduit/features/desktop_shell/domain/sheprd_view.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:conduit/features/usage/domain/usage_summary.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// The companion capability behind `sidebar-layout`: sheprd's
/// `~/.config/herdr/sidebar.toml`, read-only, as JSON.
const sheprdSidebarCapability = 'sheprd-sidebar';

/// The companion capability behind `sheprd-view` and `sheprd-view-update`
/// (CON-077): sheprd's view state, read-only, and marks sent back.
const sheprdViewCapability = 'sheprd-view';

/// The companion capability behind `sheprd-view-update --json` (CON-101):
/// layout edits sent to sheprd (contract v2).
const sheprdLayoutCapability = 'sheprd-view-2';

/// The first sheprd that applies contract v2's layout edits.
const sheprdLayoutVersion = '0.9.4';

/// The project view's state, shared by the desktop sidebar, the phone home
/// and the agents dashboard (CON-065): the layout (the app's own once
/// edited, else what the machines' sidebar.toml says, so the app and
/// sheprd agree), the view (detailed / compact), the filter (all /
/// active), collapsed projects, and every edit ("Move to project…",
/// "Move to Other", pin, rules, hide). The app's choices live in the
/// synced settings ([ThemeController.projectPrefs]); sidebar.toml is
/// never written.
class ProjectLayoutController extends ChangeNotifier {
  ProjectLayoutController({
    required this.theme,
    this.attention,
    this.refreshEvery = const Duration(minutes: 2),
    this.syncEvery = const Duration(seconds: 15),
    this.markTimeout = const Duration(minutes: 2),
    this.clock = DateTime.now,
  }) {
    theme.addListener(notifyListeners);
  }

  /// The app's one instance (main wires it); null in tests and builds
  /// without it, where the views fall back to grouping by machine only.
  static ProjectLayoutController? instance;

  final ThemeController theme;
  final AgentAttentionController? attention;
  final Duration refreshEvery;

  /// How often sheprd's view is read again while "Sync with sheprd" is on.
  final Duration syncEvery;

  /// How long a mark sent to sheprd may stay unconfirmed before it is
  /// dropped as not applied.
  final Duration markTimeout;
  final DateTime Function() clock;

  /// sidebar.toml per saved machine id, already localized (`local/` is
  /// that machine).
  final Map<String, ProjectLayout> _machineLayouts = {};
  final Map<String, String> _machineErrors = {};
  final Map<String, DateTime> _fetchedAt = {};
  final Set<String> _inFlight = {};

  /// sheprd's view per saved machine id, as that machine reported it.
  final Map<String, (SavedHost, SheprdView)> _views = {};
  final Map<String, DateTime> _viewFetchedAt = {};
  final Set<String> _viewInFlight = {};

  /// The newest view as sheprd wrote it, and the same with the pending
  /// marks shown on it ([sheprdView]).
  SheprdView? _base;
  SheprdView? _merged;

  /// A machine answered `sheprd-view` (with a view or without).
  bool _viewAnswered = false;

  /// Machines whose view.json is there but unreadable (`found: true,
  /// error`), by saved machine id: its name and why.
  final Map<String, (String, String)> _viewErrors = {};
  final Map<String, _PendingMark> _pending = {};

  /// Layout edits sent to sheprd and not confirmed yet, in sending order.
  final List<_PendingEdit> _edits = [];
  String? _markNotice;
  Map<String, String> _sheprdNames = const {};

  /// The names of the projects found from what agents report, as last
  /// built: the first edit of a layout-less view keeps them as projects.
  List<String> _found = const [];
  bool _disposed = false;

  ProjectPrefs get prefs => theme.projectPrefs;

  /// The layout read from the machines (merged), empty when none has one.
  ProjectLayout get machineLayout =>
      ProjectLayout.merge(_machineLayouts.values);

  /// Whether a machine reported a sidebar.toml.
  bool get hasMachineLayout => _machineLayouts.isNotEmpty;

  /// Machines whose sidebar.toml could not be read, with why.
  Map<String, String> get machineErrors => Map.unmodifiable(_machineErrors);

  /// Following the machines' sidebar.toml (nothing edited in the app).
  bool get followsMachines => prefs.layout == null;

  /// "Sync with sheprd" is on: the views mirror sheprd's view.
  bool get sheprdSync => prefs.sheprdSync;

  /// sheprd's view while synced: the newest any machine reported, its keys
  /// in the app's machine names. Null when off or before one was read.
  SheprdView? get sheprdView => sheprdSync ? _merged : null;

  /// Synced and some machine shares sheprd's view: the views mirror it.
  /// Synced without one, the app stays on its own layout.
  bool get mirroring => sheprdSync && _merged != null;

  /// Synced, a machine answered, and none shares sheprd's view: what to
  /// tell the user. A machine whose view.json is there but unreadable
  /// says why (CON-126); else sheprd writes none without `share_view =
  /// true`.
  String? get sheprdNotSharing {
    if (!sheprdSync || _merged != null || !_viewAnswered) return null;
    if (_viewErrors.isNotEmpty) {
      final (machine, error) = _viewErrors.values.first;
      return "sheprd's view on $machine can't be read: $error. Until then "
          'the app keeps its own projects.';
    }
    return sheprdNotSharingText;
  }

  /// A machine has sheprd's view.json, but it could not be read
  /// ([sheprdNotSharing] says why).
  bool get sheprdViewBroken =>
      sheprdNotSharing != null && _viewErrors.isNotEmpty;

  static const sheprdNotSharingText =
      "sheprd isn't sharing its view yet: set share_view = true in sheprd's "
      'sidebar.toml (sheprd ≥ 0.9.3-15). Until then the '
      'app keeps its own projects.';

  /// A mark sheprd did not apply in time ("not running?"), until
  /// [clearMarkNotice].
  String? get markNotice => sheprdSync ? _markNotice : null;

  void clearMarkNotice() {
    if (_markNotice == null) return;
    _markNotice = null;
    if (!_disposed) notifyListeners();
  }

  /// Layout edits are the app's own, or, while synced, go to a sheprd
  /// that takes them (contract v2); else they are paused.
  bool get canEditLayout => !mirroring || sheprdTakesEdits;

  /// Synced, and both sheprd and a companion that can reach it take
  /// layout edits (contract v2).
  bool get sheprdTakesEdits =>
      mirroring &&
      (_base?.takesLayoutEdits ?? false) &&
      _views.values.any((entry) => _canSendEdits(entry.$1));

  /// Synced but sheprd's layout cannot be edited from here: why.
  String? get sheprdEditsPaused {
    if (!mirroring || sheprdTakesEdits) return null;
    if (!(_base?.takesLayoutEdits ?? false)) {
      return 'Layout edits are paused: they need sheprd ≥ '
          '$sheprdLayoutVersion (it only takes marks).';
    }
    return 'Layout edits are paused: update the Conductore companion on the '
        'machine sharing sheprd\'s view.';
  }

  /// While mirroring, sheprd's layout from its view; else the app's own
  /// once edited, else the machines' sidebar.toml.
  ProjectLayout get layout =>
      mirroring ? _merged!.layout : (prefs.layout ?? machineLayout);

  bool get compact => prefs.compact ?? layout.compact ?? false;
  bool get activeOnly => prefs.activeOnly ?? layout.activeOnly ?? false;
  int get recentHours =>
      prefs.recentHours ??
      layout.recentHours ??
      ProjectPrefs.defaultRecentHours;
  bool get groupByProject => prefs.groupByProject;
  bool get showHidden => prefs.showHidden;

  /// The names a machine goes by in layout keys: its name and its address
  /// (sheprd names machines by their SSH alias).
  static Map<String, Set<String>> aliasesOf(Iterable<SavedHost> hosts) => {
    for (final host in hosts)
      baseHostId(host.id): {
        host.name.toLowerCase(),
        if (host.host.trim().isNotEmpty) host.host.trim().toLowerCase(),
      },
  };

  /// [tree] grouped by project with the current layout.
  List<ProjectGroup> build(
    List<SidebarNode> tree, {
    Map<String, List<AgentInfo>> agentsByMachine = const {},
    Iterable<SavedHost> hosts = const [],
  }) {
    if (sheprdSync && _hubWorkspaces != null) {
      final guess = _findHub(tree, hosts);
      if (guess != _hubGuess) {
        _hubGuess = guess;
        // Renames sheprd's view after this build, then builds again.
        scheduleMicrotask(() {
          if (!_disposed) _remerge();
        });
      }
    }
    final view = sheprdView;
    final groups = ProjectTreeBuilder.build(
      tree,
      agentsByMachine: agentsByMachine,
      layout: layout,
      machineAliases: aliasesOf(hosts),
      now: clock(),
      recentHours: recentHours,
      sheprd: view?.agents,
      order: view?.order ?? const [],
      sheprdStale: view?.stale ?? false,
    );
    _found = [
      for (final group in groups)
        if (!group.inLayout && !group.isOther) group.name,
    ];
    return groups;
  }

  static String _collapseKey(ProjectGroup group) =>
      group.isOther ? ProjectPrefs.otherKey : group.key;

  bool isCollapsed(ProjectGroup group) {
    final own = prefs.collapsed[_collapseKey(group)];
    if (own != null) return own;
    if (group.isOther) return layout.otherCollapsed;
    return layout.byName(group.name)?.collapsed ?? false;
  }

  /// The entries [group] shows under the current filter.
  List<ProjectEntry> visibleEntries(ProjectGroup group) => [
    for (final entry in group.entries)
      if ((!entry.hidden || showHidden) && (!activeOnly || entry.active)) entry,
  ];

  /// Whether the agent [row] of [entry] is left out by the active filter.
  /// The same rule decides as for the workspace ([ProjectEntry.active]):
  /// while sheprd decides ([ProjectEntry.bySheprd]), its active view (idle
  /// too long, or removed by hand: out), or busy for an agent it has not
  /// listed yet; else busy, open in the app, or changed state within the
  /// recent hours. Every project view uses this, so they agree.
  bool leftOutOfActive(ProjectEntry entry, SidebarNode row) {
    if (!activeOnly) return false;
    if (!entry.active) return true;
    final dot = entry.dotOf(row);
    if (entry.bySheprd) {
      return !(entry.sheprdOf(row)?.active ?? ProjectTreeBuilder.isBusy(dot));
    }
    if (entry.node.openInApp || row.openInApp) return false;
    if (dot != SidebarDot.idle) return false;
    final at = ProjectTreeBuilder.agentOf(row)?.stateChangedAt;
    return at == null || clock().difference(at) >= Duration(hours: recentHours);
  }

  /// Groups the view lists: Other and (with the active filter) projects
  /// with nothing to show are left out, like in sheprd.
  List<ProjectGroup> visibleGroups(List<ProjectGroup> groups) => [
    for (final group in groups)
      if (visibleEntries(group).isNotEmpty || (!group.isOther && !activeOnly))
        group,
  ];

  /// Agents needing you across [groups], hidden rows left out.
  static int needsYouCount(List<ProjectGroup> groups) =>
      groups.fold(0, (sum, group) => sum + group.needsYou);

  // View choices.

  Future<void> _setPrefs(ProjectPrefs next) => theme.setProjectPrefs(next);

  Future<void> toggleCollapsed(ProjectGroup group) => _setPrefs(
    prefs.copyWith(
      collapsed: {...prefs.collapsed, _collapseKey(group): !isCollapsed(group)},
    ),
  );

  Future<void> setCompact(bool compact) =>
      _setPrefs(prefs.copyWith(compact: compact));

  Future<void> setActiveOnly(bool activeOnly) =>
      _setPrefs(prefs.copyWith(activeOnly: activeOnly));

  Future<void> setRecentHours(int hours) =>
      _setPrefs(prefs.copyWith(recentHours: hours.clamp(1, 24 * 30)));

  Future<void> setGroupByProject(bool on) =>
      _setPrefs(prefs.copyWith(groupByProject: on));

  Future<void> setShowHidden(bool on) =>
      _setPrefs(prefs.copyWith(showHidden: on));

  /// Turns "Sync with sheprd" on or off. Off brings the app's own layout
  /// back as it was; on reads sheprd's view now.
  Future<void> setSheprdSync(bool on) async {
    await _setPrefs(prefs.copyWith(sheprdSync: on));
    if (on) await refresh(force: true);
  }

  /// The app came back to the foreground: while synced, sheprd's view is
  /// read again now, whatever screen shows (CON-126), so the home screen
  /// and the widget never start from a view minutes old.
  Future<void> appResumed() async {
    if (_disposed || !sheprdSync) return;
    await refresh(force: true);
  }

  // Layout edits: the app's own layout from here on.

  /// The layout edits start from: the app's own, else the machines', else
  /// the projects found from the agents (each with its name as a rule, so
  /// they keep their workspaces).
  ProjectLayout get _editable {
    final own = prefs.layout;
    if (own != null) return own;
    final machines = machineLayout;
    if (machines.groups.isNotEmpty) return machines;
    var layout = machines;
    for (final name in _found) {
      layout = layout.add(name, rules: [name]);
    }
    return layout;
  }

  /// The app's own layout edit; while synced, [sheprd]'s edits go to
  /// sheprd instead (none: paused).
  Future<void> _editLayout(
    ProjectLayout Function(ProjectLayout) edit, {
    List<SheprdLayoutEdit> Function()? sheprd,
  }) async {
    if (mirroring) {
      if (!sheprdTakesEdits || sheprd == null) return;
      final edits = sheprd();
      if (edits.isEmpty) return;
      final error = await sendEdits(edits);
      if (error != null && !_disposed) {
        _markNotice = error;
        notifyListeners();
      }
      return;
    }
    await _setPrefs(prefs.copyWith(layout: edit(_editable)));
  }

  /// "Move to project…" ([project] made when missing) and "Move to Other"
  /// (an empty [project]).
  Future<void> moveTo(ProjectEntry entry, String project) => _editLayout(
    (layout) => layout.assign(entry.memberKey, project),
    sheprd: () => [SheprdLayoutEdit.assign(entry.memberKey, project.trim())],
  );

  Future<void> toggleHidden(ProjectEntry entry) => _editLayout(
    (layout) => layout.toggleHidden(entry.memberKey),
    sheprd: () => [
      SheprdLayoutEdit.hide(
        entry.memberKey,
        hidden: !layout.isHidden(entry.memberKey),
      ),
    ],
  );

  /// Moves [entry] one place up (-1) or down (1) in [group].
  Future<void> moveEntry(ProjectGroup group, ProjectEntry entry, int delta) {
    final keys = [for (final e in group.entries) e.memberKey];
    final at = keys.indexOf(entry.memberKey);
    final to = at + delta;
    if (group.isOther || at < 0 || to < 0 || to >= keys.length) {
      return Future.value();
    }
    final before = delta < 0
        ? keys[to]
        : (to + 1 < keys.length ? keys[to + 1] : '');
    return _editProject(
      group,
      (layout, name) => layout.moveMember(name, keys, entry.memberKey, before),
      sheprd: (_) => [
        SheprdLayoutEdit.moveMember(
          entry.memberKey,
          before,
          project: group.name,
          inView: keys,
        ),
      ],
    );
  }

  /// Whether [entry] can move by [delta] in [group].
  static bool canMoveEntry(ProjectGroup group, ProjectEntry entry, int delta) {
    if (group.isOther) return false;
    final at = group.entries.indexOf(entry);
    return at >= 0 && at + delta >= 0 && at + delta < group.entries.length;
  }

  /// Takes the agent [row] of [entry] out of sheprd's active view, or
  /// keeps it there ([remove] false), like sheprd's own menu.
  Future<String?> setActive(
    ProjectEntry entry,
    SidebarNode row, {
    required bool remove,
  }) async {
    final key = entry.sheprdKeys[row.key];
    if (key == null || !sheprdTakesEdits) return 'Not synced with sheprd.';
    if (!remove) return sendEdits([SheprdLayoutEdit.keepActive(key)]);
    final seq = entry.sheprdOf(row)?.stateSeq ?? _liveSequence(row);
    if (seq == null) return 'sheprd has not seen this agent change state yet.';
    return sendEdits([SheprdLayoutEdit.removeActive(key, seq)]);
  }

  /// [edit] on [group]'s own entry in the layout (made for a project
  /// found from the agents). While synced, [sheprd]'s edits for its name
  /// in sheprd's layout, after creating it there when it is missing
  /// (with its name as a rule, so it keeps its workspaces).
  Future<void> _editProject(
    ProjectGroup group,
    ProjectLayout Function(ProjectLayout layout, String name) edit, {
    List<SheprdLayoutEdit> Function(String name)? sheprd,
  }) => _editLayout(
    (layout) {
      final withGroup = layout.add(group.name);
      return edit(withGroup, withGroup.byName(group.name)!.name);
    },
    sheprd: sheprd == null
        ? null
        : () {
            final def = layout.byName(group.name);
            if (def != null) return sheprd(def.name);
            final name = group.name.trim();
            return [
              SheprdLayoutEdit.createProject(name, match: [name.toLowerCase()]),
              ...sheprd(name),
            ];
          },
  );

  Future<void> setPinned(ProjectGroup group, bool pinned) => _editProject(
    group,
    (layout, name) => layout.setPinned(name, pinned),
    sheprd: (name) => [SheprdLayoutEdit.pin(name, pinned: pinned)],
  );

  Future<void> setRules(ProjectGroup group, List<String> rules) => _editProject(
    group,
    (layout, name) => layout.setRules(name, rules),
    sheprd: (name) => [
      SheprdLayoutEdit.rules(
        name,
        _cleanRules(rules),
        was: _base?.layout.byName(name)?.match,
      ),
    ],
  );

  /// Rules as the layout keeps them: trimmed, lower-cased, no blanks,
  /// repeats or commas.
  static List<String> _cleanRules(Iterable<String> rules) => {
    for (final rule in rules)
      for (final part in rule.split(','))
        if (part.trim().isNotEmpty) part.trim().toLowerCase(),
  }.toList();

  /// Renames [group]; a name another project has is refused (false).
  Future<bool> renameProject(ProjectGroup group, String to) async {
    final next = to.trim();
    if (next.isEmpty || next == group.name) return false;
    final taken = layout.byName(next);
    if (taken != null && taken.name.toLowerCase() != group.name.toLowerCase()) {
      return false;
    }
    await _editProject(
      group,
      (layout, name) => layout.rename(name, next),
      sheprd: (name) => [SheprdLayoutEdit.rename(name, next)],
    );
    return true;
  }

  /// Sets [group]'s two-letter tag; empty goes back to the derived one.
  Future<void> setShort(ProjectGroup group, String short) => _editProject(
    group,
    (layout, name) => layout.setShort(name, short),
    sheprd: (name) => [SheprdLayoutEdit.short(name, short.trim())],
  );

  /// The project [group] would move before for [delta] (-1 up, 1 down)
  /// in display order, '' for the end of its pin section; null when it
  /// cannot move that way (top, bottom, or across the pinned ones).
  String? _moveTarget(ProjectGroup group, int delta) {
    final layout = this.layout;
    final def = layout.byName(group.name);
    if (def == null) return null;
    final order = [
      for (final i in layout.displayOrder)
        if (layout.groups[i].pinned == def.pinned) layout.groups[i].name,
    ];
    final at = order.indexOf(def.name);
    final to = at + delta;
    if (at < 0 || to < 0 || to >= order.length) return null;
    if (delta < 0) return order[to];
    return to + 1 < order.length ? order[to + 1] : '';
  }

  bool canMoveProject(ProjectGroup group, int delta) =>
      _moveTarget(group, delta) != null;

  /// Moves [group] one place up (-1) or down (1) among the projects with
  /// the same pin.
  Future<void> moveProject(ProjectGroup group, int delta) async {
    final before = _moveTarget(group, delta);
    if (before == null) return;
    final name = layout.byName(group.name)!.name;
    await _editLayout(
      (layout) => layout.moveGroup(name, before),
      sheprd: () => [SheprdLayoutEdit.moveProject(name, before)],
    );
  }

  Future<void> addProject(String name, {List<String> rules = const []}) =>
      _editLayout(
        (layout) => layout.add(name, rules: rules),
        sheprd: () {
          final def = layout.byName(name.trim());
          if (def == null) {
            return [
              SheprdLayoutEdit.createProject(
                name.trim(),
                match: _cleanRules(rules),
              ),
            ];
          }
          return [
            SheprdLayoutEdit.rules(
              def.name,
              _cleanRules([...def.match, ...rules]),
              was: def.match,
            ),
          ];
        },
      );

  Future<void> removeProject(ProjectGroup group) => _editLayout(
    (layout) {
      final def = layout.byName(group.name);
      return def == null ? layout : layout.remove(def.name);
    },
    sheprd: () {
      final def = layout.byName(group.name);
      if (def == null) return const [];
      final shown = _base?.layout.byName(def.name);
      return [SheprdLayoutEdit.delete(def.name, members: shown?.members)];
    },
  );

  /// Back to the machines' sidebar.toml: drops what was edited in the app.
  Future<void> followMachineLayout() async {
    if (mirroring) return;
    await _setPrefs(prefs.copyWith(clearLayout: true));
  }

  /// Project names to offer in "Move to project…": the layout's, then
  /// those found from the agents.
  List<String> get projectNames => {
    for (final index in layout.displayOrder) layout.groups[index].name,
    ..._found,
  }.toList();

  /// The project of one agent seen without the machine tree (the agents
  /// dashboard): its Herdr workspace or tmux session on machine [host] as
  /// the layout places it (listed, else caught by a rule on its repo or
  /// folder), else Other. With no layout projects, the repo it reports
  /// (CON-032), else Other. Returns the project's name; Other is
  /// [ProjectGroup.otherKey].
  String projectOfAgent(SavedHost host, {AgentInfo? live, String? project}) {
    final layout = this.layout;
    final repo = project ?? live?.repoLabel;
    final names = aliasesOf([host]).values.single;
    final workspace = live?.workspace?.trim() ?? '';
    final tab = live?.tab?.trim() ?? '';
    final keys = [
      for (final name in names) ...[
        if (RegExp(r'^w[A-Za-z0-9]+$').hasMatch(workspace))
          ProjectKeys.herdr(name, workspace, ''),
        if (tab.isNotEmpty && !RegExp(r'^w[A-Za-z0-9]+$').hasMatch(workspace))
          ProjectKeys.named(name, tab.split(':').first),
      ],
    ];
    if (keys.any(layout.isUngrouped)) return ProjectGroup.otherKey;
    if (layout.groups.isEmpty) return repo ?? ProjectGroup.otherKey;
    for (final key in keys) {
      final explicit = layout.explicitGroup(key);
      if (explicit != null) return layout.groups[explicit].name;
    }
    final index = layout.groupOf('', [
      ?repo,
      if (workspace.startsWith('/') || workspace.startsWith('~')) workspace,
    ]);
    return index == null ? ProjectGroup.otherKey : layout.groups[index].name;
  }

  /// [agent] on [host] as the launcher's `project` and `active` columns
  /// read it (CON-119): its project as [projectOfAgent] places it (null
  /// for Other), and whether the "active" filter keeps it whatever its
  /// last change: with "Sync with sheprd", what sheprd's active view says
  /// of its pane; else busy, the dots the filter keeps (working, needing
  /// you, finished). A change within [recentHours] keeps it too; the
  /// launcher's side judges that when asked.
  ({String? project, bool busy}) launcherFacts(
    SavedHost host,
    AgentInfo agent,
  ) {
    final project = projectOfAgent(host, live: agent);
    final view = sheprdView;
    SheprdAgentView? synced;
    if (view != null) {
      final pane = agent.pane ?? agent.id;
      for (final name in aliasesOf([host]).values.single) {
        synced = view.agents['$name/$pane'];
        if (synced != null) break;
      }
    }
    return (
      project: project == ProjectGroup.otherKey ? null : project,
      busy:
          synced?.active ??
          switch (SidebarDot.of(agent.state)) {
            SidebarDot.needsYou ||
            SidebarDot.working ||
            SidebarDot.done => true,
            _ => false,
          },
    );
  }

  // sidebar.toml from the machines.

  /// Asks every machine whose companion can tell for its sidebar.toml,
  /// at most every [refreshEvery] (or now with [force]).
  Future<void> refresh({bool force = false}) async {
    final attention = this.attention;
    final hosts = viewHosts ?? attention?.monitoredHosts;
    if (hosts == null) return;
    final now = clock();
    final seen = <String>{};
    final pending = <Future<void>>[];
    for (final host in hosts) {
      final id = baseHostId(host.id);
      if (!seen.add(id)) continue;
      if (host.backend == HostBackend.hc) {
        // The Herdr app's layout, not sheprd's files (CON-130).
        if (_views.remove(id) != null) _remerge();
        final last = _fetchedAt[id];
        if ((force || last == null || now.difference(last) >= refreshEvery) &&
            !_inFlight.contains(id) &&
            (sheprdRunner != null || attention != null)) {
          pending.add(_fetchHc(host, id));
        }
        continue;
      }
      if (sheprdSync && _canSend(host)) {
        final last = _viewFetchedAt[id];
        if ((force || last == null || now.difference(last) >= syncEvery) &&
            !_viewInFlight.contains(id)) {
          pending.add(_fetchView(host, id));
        }
      }
      if (attention == null ||
          !attention.companionSupports(host.id, sheprdSidebarCapability)) {
        continue;
      }
      final last = _fetchedAt[id];
      if (!force && last != null && now.difference(last) < refreshEvery) {
        continue;
      }
      if (_inFlight.contains(id)) continue;
      pending.add(_fetch(attention, host, id));
    }
    await Future.wait(pending);
  }

  Future<void> _fetch(
    AgentAttentionController attention,
    SavedHost host,
    String id,
  ) async {
    _inFlight.add(id);
    _fetchedAt[id] = clock();
    final (runner, :owned) = attention.runnerFor(host);
    try {
      final result = await runner.run(
        ConductoreHostAttentionProvider.remoteCommand('sidebar-layout'),
        timeout: const Duration(seconds: 15),
      );
      applyReply(host, result.stdout);
    } catch (_) {
      // Unreachable now: the next refresh asks again.
    } finally {
      _inFlight.remove(id);
      if (owned) unawaited(runner.close());
    }
  }

  /// The Herdr app sidebar's `sheprd-view` as [host]'s layout: the
  /// machine's own document, else the first machine it reaches that has
  /// one (the app's hub, usually the laptop).
  Future<void> _fetchHc(SavedHost host, String id) async {
    _inFlight.add(id);
    _fetchedAt[id] = clock();
    try {
      const names = [HcDocuments.view];
      var view = HcSheprdView.fromJson(
        HcListing.parseDocAnswers(
          await _run(host, HcCommands.docGet(names)),
        )[1],
      );
      if (view == null) {
        final machines = _hcMachines(await _run(host, HcCommands.ls));
        if (machines.isNotEmpty) {
          final answers = HcListing.parseDocAnswers(
            await _run(
              host,
              HcCommands.docGet(names, on: machines, skipLocal: true),
            ),
          );
          for (var i = 0; i < machines.length && view == null; i++) {
            view = HcSheprdView.fromJson(answers[i + 1]);
          }
        }
      }
      applyHcView(host, view);
    } catch (_) {
      // Unreachable now: the next refresh asks again.
    } finally {
      _inFlight.remove(id);
    }
  }

  /// The machines `hc ls --json` says hc reaches.
  static List<String> _hcMachines(String stdout) {
    try {
      final decoded = jsonDecode(stdout.trim());
      return [
        if (decoded is Map && decoded['machines'] is List)
          for (final machine in decoded['machines'] as List)
            if (machine is Map && machine['name'] is String)
              machine['name'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Takes the Herdr app's view for hc machine [host]; null clears it.
  @visibleForTesting
  void applyHcView(SavedHost host, HcSheprdView? view) {
    final id = baseHostId(host.id);
    final before = _machineLayouts[id];
    if (view == null) {
      _machineLayouts.remove(id);
    } else {
      _machineLayouts[id] = view.toProjectLayout(host.name);
    }
    if (before != _machineLayouts[id] && !_disposed) notifyListeners();
  }

  /// Takes one `sidebar-layout` reply from [host].
  @visibleForTesting
  void applyReply(SavedHost host, String stdout) {
    final id = baseHostId(host.id);
    Object? decoded;
    try {
      final lines = stdout.trim().split('\n');
      decoded = jsonDecode(lines.last);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final before = (_machineLayouts[id], _machineErrors[id]);
    _machineErrors.remove(id);
    if (decoded['found'] != true) {
      _machineLayouts.remove(id);
    } else if (decoded['error'] is String) {
      _machineLayouts.remove(id);
      _machineErrors[id] = decoded['error'] as String;
    } else {
      _machineLayouts[id] = ProjectLayout.fromJson(
        decoded['layout'],
      ).localized(host.name.toLowerCase());
    }
    if (before != (_machineLayouts[id], _machineErrors[id]) && !_disposed) {
      notifyListeners();
    }
  }

  // sheprd's view (CON-077).

  Future<void> _fetchView(SavedHost host, String id) async {
    _viewInFlight.add(id);
    _viewFetchedAt[id] = clock();
    try {
      applyViewReply(
        host,
        await _run(
          host,
          ConductoreHostAttentionProvider.remoteCommand('sheprd-view'),
        ),
      );
    } catch (_) {
      // Unreachable now: the next refresh asks again.
    } finally {
      _viewInFlight.remove(id);
    }
  }

  /// Takes one `sheprd-view` reply from [host].
  @visibleForTesting
  void applyViewReply(SavedHost host, String stdout) {
    Object? decoded;
    try {
      decoded = jsonDecode(stdout.trim().split('\n').last);
    } catch (_) {
      return;
    }
    final id = baseHostId(host.id);
    final view = SheprdView.fromReply(decoded);
    final error = view == null && decoded is Map && decoded['found'] == true
        ? (decoded['error'] is String
              ? decoded['error'] as String
              : 'view.json is not one this app reads')
        : null;
    final hadError = _viewErrors[id];
    if (error == null) {
      _viewErrors.remove(id);
    } else {
      _viewErrors[id] = (host.name, error);
    }
    if (!_viewAnswered || hadError != _viewErrors[id]) {
      _viewAnswered = true;
      if (view == null && !_disposed) notifyListeners();
    }
    if (view == null) {
      if (_views.remove(id) == null) return;
    } else {
      if (_views[id]?.$2 == view) return;
      _views[id] = (host, view);
    }
    _remerge();
  }

  /// sheprd names machines by the hub's endpoint labels and the hub itself
  /// `local`, in every machine's copy. A machine's own copy says which
  /// label is that machine (`self`). The hub is the machine whose copy
  /// says `local`; else the one named like the hub (name, address, or
  /// their first dot-separated part); else the machine whose Herdr
  /// workspaces are the view's `local/` ones ([build] finds it, CON-126).
  void _remerge() {
    final names = <String, String>{};
    String? hub;
    String? hubName;
    for (final (host, view) in _views.values) {
      final name = host.name.toLowerCase();
      hubName ??= view.hub;
      if (view.fromHub) {
        hub = name;
      } else {
        names[view.self] = name;
      }
    }
    if (hub == null && hubName != null) {
      final hosts = [
        ...?attention?.monitoredHosts,
        ...?viewHosts,
        for (final (host, _) in _views.values) host,
      ];
      for (final host in hosts) {
        if (_namesOf(host).contains(hubName)) {
          hub = host.name.toLowerCase();
          break;
        }
      }
    }
    final newest = [for (final (_, view) in _views.values) view]
      ..sort((a, b) {
        final byTime = b.updated.compareTo(a.updated);
        if (byTime != 0) return byTime;
        return (b.fromHub ? 1 : 0) - (a.fromHub ? 1 : 0);
      });
    // Found by name or by its own copy: no guessing needed.
    _hubWorkspaces = hub == null && newest.isNotEmpty
        ? _localWorkspaces(newest.first)
        : null;
    if (hub == null && _hubWorkspaces != null) hub = _hubGuess;
    _hubMissing = hub == null && newest.isNotEmpty
        ? (hubName ?? 'local')
        : null;
    names['local'] = hub ?? hubName ?? 'local';
    _sheprdNames = names;
    _base = newest.isEmpty ? null : newest.first.renamed(names);
    _confirmPending();
    _overlay();
    if (!_disposed) notifyListeners();
  }

  /// The names [host] may go by in sheprd: its name and address, and the
  /// first part of each (`omarchy` for `omarchy.tail1234.ts.net`).
  static Set<String> _namesOf(SavedHost host) => {
    for (final name in aliasesOf([host]).values.single) ...{
      name,
      // Not for an IP address.
      if (!RegExp(r'^[\d.:]+$').hasMatch(name)) name.split('.').first,
    },
  };

  /// The hub's workspaces in [view] (`id:label`, lower case), while the
  /// hub is not known by name; null once it is.
  Set<String>? _hubWorkspaces;

  /// The machine [build] found holding the hub's workspaces.
  String? _hubGuess;

  /// sheprd's name for a hub that is none of the machines here.
  String? _hubMissing;

  static Set<String> _localWorkspaces(SheprdView view) {
    final layout = view.layout;
    return {
      for (final key in [
        ...view.order,
        ...layout.hidden,
        ...layout.ungrouped,
        for (final group in layout.groups) ...group.members,
      ])
        if (key.startsWith('local/') && key.contains(':'))
          key.substring('local/'.length).toLowerCase(),
    };
  }

  /// While the hub is unknown by name: the machine in [tree], not named
  /// by another machine's copy, with the most of the hub's workspaces
  /// (by Herdr id and label), if one has more than any other.
  String? _findHub(List<SidebarNode> tree, Iterable<SavedHost> hosts) {
    final wanted = _hubWorkspaces;
    if (wanted == null || wanted.isEmpty) return null;
    final taken = {
      for (final MapEntry(:key, :value) in _sheprdNames.entries)
        if (key != 'local') value,
    };
    final byId = {for (final host in hosts) baseHostId(host.id): host};
    final counts = <String, int>{};
    for (final machine in tree) {
      final host = byId[baseHostId(machine.machineId)];
      final name = (host?.name ?? machine.label).toLowerCase();
      if (taken.contains(name)) continue;
      var count = 0;
      for (final node in machine.children) {
        if (node.target case HerdrWorkspaceTarget(:final workspace)) {
          final key = '${workspace.workspace.id}:${workspace.workspace.label}'
              .toLowerCase();
          if (wanted.contains(key)) count += 1;
        }
      }
      if (count > 0) counts[name] = count;
    }
    if (counts.isEmpty) return null;
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.length > 1 && ranked[1].value == ranked[0].value) return null;
    return ranked.first.key;
  }

  /// Synced, and sheprd's hub is none of the machines here: its agents
  /// keep the app's own status, and the view says why.
  String? get sheprdHubMissing => mirroring && _hubMissing != null
      ? "sheprd's hub '$_hubMissing' isn't one of your machines: its "
            "agents show the app's own status. Name that machine "
            "'$_hubMissing' here, or connect its companion."
      : null;

  /// [key] (`machine/pane_id` in the app's names) as sheprd names it.
  String _sheprdKey(String key) {
    final back = {
      for (final MapEntry(:key, :value) in _sheprdNames.entries) value: key,
    };
    return ProjectKeys.renamed(key, back);
  }

  /// Sends [mark] for the agent [row] of [entry] back to sheprd, through a
  /// machine whose companion has sheprd's view (the agent's own first),
  /// and shows it at once. Returns why it failed, null when sent.
  Future<String?> mark(
    ProjectEntry entry,
    SidebarNode row,
    SheprdMark mark,
  ) async {
    final key = entry.sheprdKeys[row.key];
    if (key == null || !mirroring) return 'Not synced with sheprd.';
    final senders = [
      for (final MapEntry(key: id, value: (host, _)) in _views.entries)
        if (_canSend(host)) (id == baseHostId(row.machineId) ? 0 : 1, host),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (senders.isEmpty) return "No machine has sheprd's view.";
    final host = senders.first.$2;
    final view = entry.sheprdOf(row);
    final seq = view?.stateSeq ?? _liveSequence(row);
    if (mark == SheprdMark.dismiss && seq == null) {
      return 'sheprd has not seen this agent change state yet.';
    }
    final args = [
      'sheprd-view-update',
      '--op',
      mark.name,
      '--agent',
      shellQuoteArgument(_sheprdKey(key)),
      if (mark == SheprdMark.dismiss) ...['--state-seq', '$seq'],
    ].join(' ');
    try {
      final stdout = await _run(
        host,
        ConductoreHostAttentionProvider.remoteCommand(args),
      );
      final reply = jsonDecode(stdout.trim().split('\n').last);
      if (reply is Map && reply['ok'] == true) {
        _showMark(key, mark);
        return null;
      }
      return reply is Map && reply['error'] is String
          ? reply['error'] as String
          : 'sheprd-view-update failed.';
    } catch (_) {
      return 'Could not reach ${host.name}.';
    }
  }

  /// Sends [edits] to sheprd in one append (contract v2), through a
  /// machine whose companion takes them (the hub's first), and shows them
  /// at once. Returns why it failed, null when sent.
  Future<String?> sendEdits(List<SheprdLayoutEdit> edits) async {
    if (!sheprdTakesEdits) {
      return sheprdEditsPaused ?? 'Not synced with sheprd.';
    }
    final senders = [
      for (final (host, view) in _views.values)
        if (_canSendEdits(host)) (view.fromHub ? 0 : 1, host),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final host = senders.first.$2;
    final json = jsonEncode([
      for (final edit in edits) edit.toJson(_sheprdKey),
    ]);
    try {
      final stdout = await _run(
        host,
        ConductoreHostAttentionProvider.remoteCommand(
          'sheprd-view-update --json ${shellQuoteArgument(json)}',
        ),
      );
      final reply = jsonDecode(stdout.trim().split('\n').last);
      if (reply is Map && reply['ok'] == true) {
        final ids = [
          if (reply['ids'] case final List<Object?> ids)
            for (final id in ids) '$id',
        ];
        final since = _base?.updated ?? 0;
        for (final (i, edit) in edits.indexed) {
          final id = i < ids.length ? ids[i] : '';
          _edits.add(
            _PendingEdit(
              edit,
              id: id,
              since: since,
              timer: Timer(markTimeout, () => _expireEdit(id, edit)),
            ),
          );
        }
        _overlay();
        if (!_disposed) notifyListeners();
        return null;
      }
      return reply is Map && reply['error'] is String
          ? reply['error'] as String
          : 'sheprd-view-update failed.';
    } catch (_) {
      return 'Could not reach ${host.name}.';
    }
  }

  void _expireEdit(String id, SheprdLayoutEdit edit) {
    final at = _edits.indexWhere((p) => p.id == id && p.edit == edit);
    if (at < 0 || _disposed) return;
    _edits.removeAt(at);
    _markNotice = "sheprd didn't apply this (not running?): ${edit.label}";
    _overlay();
    notifyListeners();
  }

  /// Layout edits sent to sheprd and not confirmed yet.
  List<SheprdLayoutEdit> get pendingEdits =>
      sheprdSync ? [for (final p in _edits) p.edit] : const [];

  /// Whether an edit about project [name] waits for sheprd.
  bool projectPending(String name) => pendingEdits.any(
    (edit) =>
        edit.project != null &&
        edit.workspace == null &&
        (edit.project!.toLowerCase() == name.toLowerCase() ||
            edit.to?.toLowerCase() == name.toLowerCase()),
  );

  /// Whether an edit about workspace [entry] (or one of its agents) waits
  /// for sheprd.
  bool entryPending(ProjectEntry entry) => pendingEdits.any(
    (edit) =>
        (edit.workspace != null &&
            ProjectKeys.same(edit.workspace!, entry.memberKey)) ||
        (edit.agent != null && entry.sheprdKeys.containsValue(edit.agent)),
  );

  /// Whether an edit about [group] or one of its rows waits for sheprd.
  bool groupPending(ProjectGroup group) =>
      _edits.isNotEmpty &&
      sheprdSync &&
      ((!group.isOther && projectPending(group.name)) ||
          group.entries.any(entryPending));

  /// Runs marks in tests instead of a machine's companion.
  @visibleForTesting
  Future<String> Function(SavedHost host, String command)? sheprdRunner;

  /// Tests set this: the machines asked for sheprd's view, instead of the
  /// monitored ones.
  @visibleForTesting
  List<SavedHost>? viewHosts;

  bool _canSend(SavedHost host) =>
      sheprdRunner != null ||
      (attention?.companionSupports(host.id, sheprdViewCapability) ?? false);

  /// Tests set this to say which machines' companions take layout edits.
  @visibleForTesting
  bool Function(SavedHost host)? editCapable;

  bool _canSendEdits(SavedHost host) =>
      editCapable?.call(host) ??
      (attention?.companionSupports(host.id, sheprdLayoutCapability) ?? false);

  Future<String> _run(SavedHost host, String command) async {
    if (sheprdRunner case final run?) return run(host, command);
    final (runner, :owned) = attention!.runnerFor(host);
    try {
      final result = await runner.run(
        command,
        timeout: const Duration(seconds: 15),
      );
      return result.stdout;
    } finally {
      if (owned) unawaited(runner.close());
    }
  }

  static int? _liveSequence(SidebarNode row) => switch (row.target) {
    AgentPaneTarget(:final pane) => pane.agent.stateSequence,
    _ => null,
  };

  /// Waits for sheprd to confirm [mark]: shown as pending until a newer
  /// view reflects it, dropped with a notice after [markTimeout].
  void _showMark(String key, SheprdMark mark) {
    _pending.remove(key)?.timer.cancel();
    _pending[key] = _PendingMark(
      mark,
      since: _base?.updated ?? 0,
      timer: Timer(markTimeout, () => _expire(key)),
    );
    _overlay();
    if (!_disposed) notifyListeners();
  }

  void _expire(String key) {
    final pending = _pending.remove(key);
    if (pending == null || _disposed) return;
    _markNotice =
        "sheprd didn't apply this (not running?): "
        '${pending.mark.label.toLowerCase()}';
    _overlay();
    notifyListeners();
  }

  /// Drops the pending marks a view newer than their sending reflects.
  void _confirmPending() {
    final base = _base;
    if (base == null) return;
    _pending.removeWhere((key, pending) {
      final view = base.agents[key];
      final done =
          base.updated > pending.since &&
          view != null &&
          view.reflects(pending.mark);
      if (done) pending.timer.cancel();
      return done;
    });
    String? refused;
    _edits.removeWhere((pending) {
      final why = base.rejected[pending.id];
      if (why != null) {
        refused =
            "sheprd refused ${pending.edit.label}${why.isEmpty ? '' : ': $why'}";
      }
      final done =
          why != null ||
          (base.updated > pending.since && pending.edit.reflectedIn(base));
      if (done) pending.timer.cancel();
      return done;
    });
    if (refused != null) _markNotice = refused;
  }

  void _overlay() {
    var view = _base;
    if (view != null) {
      for (final MapEntry(:key, value: pending) in _pending.entries) {
        final agent =
            view!.agents[key] ??
            const SheprdAgentView(presence: SheprdPresence.idle);
        view = view.withAgent(key, agent.withPending(pending.mark));
      }
      for (final pending in _edits) {
        view = pending.edit.applyTo(view!);
      }
    }
    _merged = view;
  }

  // Per-project usage.

  /// Today's tokens per project key (input, output and cache writes; cache
  /// reads left out, like sheprd), from the usage reports the app already
  /// has: each report row's repo goes to the project whose agents report
  /// it, else whose rule catches it, else Other. Empty without reports.
  Map<String, int> tokensToday(List<ProjectGroup> groups, UsageSummary usage) {
    final byRepo = <String, String>{};
    for (final group in groups) {
      for (final (_, agent) in group.agents) {
        final repo = agent.repoLabel?.toLowerCase();
        if (repo != null) byRepo.putIfAbsent(repo, () => group.key);
      }
    }
    final layout = this.layout;
    final keys = {for (final group in groups) group.key};
    final result = <String, int>{};
    for (final machine in usage.machines) {
      final report = machine.report;
      if (report == null) continue;
      for (final row in [...report.claude.rows, ...report.codex.rows]) {
        if (row.date != report.today || row.hour != null) continue;
        final repo = row.project.toLowerCase();
        var key = byRepo[repo];
        if (key == null && layout.groups.isNotEmpty) {
          final index = layout.groupOf('', [row.project]);
          if (index != null) key = layout.groups[index].name.toLowerCase();
        }
        key ??= keys.contains(repo) ? repo : ProjectGroup.otherKey;
        final totals = row.totals;
        result[key] =
            (result[key] ?? 0) +
            totals.input +
            totals.output +
            totals.cacheWrite;
      }
    }
    return result;
  }

  /// Asks again every [syncEvery] while a project view shows ([watch]): a
  /// rebuild alone is not enough, since a status poll that found nothing
  /// new rebuilds nothing, and sheprd's edits (moves, names) never showed.
  Timer? _ticker;
  int _watchers = 0;

  /// Keeps the machines' layouts and sheprd's view fresh until the returned
  /// callback is called; only while the app is in the foreground.
  VoidCallback watch() {
    _watchers += 1;
    if (!_disposed) {
      _ticker ??= Timer.periodic(syncEvery, (_) {
        final state = SchedulerBinding.instance.lifecycleState;
        if (state == null || state == AppLifecycleState.resumed) {
          unawaited(refresh());
        }
      });
    }
    var done = false;
    return () {
      if (done) return;
      done = true;
      _watchers -= 1;
      if (_watchers > 0) return;
      _ticker?.cancel();
      _ticker = null;
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    for (final pending in _pending.values) {
      pending.timer.cancel();
    }
    for (final pending in _edits) {
      pending.timer.cancel();
    }
    theme.removeListener(notifyListeners);
    super.dispose();
  }
}

/// "1.2M" / "340k" / "900", like sheprd.
String formatProjectTokens(int tokens) {
  if (tokens < 1000) return '$tokens';
  if (tokens < 1000000) return '${tokens ~/ 1000}k';
  return '${(tokens / 1000000).toStringAsFixed(1)}M';
}

/// A mark sent to sheprd, waiting for a view newer than [since] to show it.
class _PendingMark {
  _PendingMark(this.mark, {required this.since, required this.timer});

  final SheprdMark mark;
  final int since;
  final Timer timer;
}

/// A layout edit sent to sheprd as line [id], waiting for a view newer
/// than [since] to show it (or to list [id] as refused).
class _PendingEdit {
  _PendingEdit(
    this.edit, {
    required this.id,
    required this.since,
    required this.timer,
  });

  final SheprdLayoutEdit edit;
  final String id;
  final int since;
  final Timer timer;
}
