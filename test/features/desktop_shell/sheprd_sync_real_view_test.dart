import 'dart:convert';
import 'dart:io';

import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/desktop_shell/domain/project_tree.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:conduit/features/desktop_shell/presentation/project_layout_controller.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

// CON-126: with sync on, the phone listed many more active rows than
// sheprd. The fixture is the relayed view.json from dev-central
// (2026-10-31, stripped to 15 agents): sheprd's active view holds 6 of
// these rows; every other agent is idle for more than a day or was
// removed from active by hand.

SavedHost _host(String id, String name) => SavedHost(
  id: id,
  name: name,
  host: '$name.tail',
  port: 22,
  username: 'u',
  authMethod: SshAuthMethod.password,
);

/// A machine's Herdr workspaces, each with its agents, as the app lists
/// them.
SidebarNode _machine(
  SavedHost host,
  Map<(String, String), List<AgentInfo>> workspaces,
) => SidebarNode(
  key: SidebarKeys.machine(host.id),
  kind: SidebarNodeKind.machine,
  machineId: host.id,
  label: host.name,
  target: MachineTarget(host),
  children: [
    for (final MapEntry(key: (wsId, label), value: agents)
        in workspaces.entries)
      () {
        final workspace = HomeBoardWorkspace(
          workspace: HerdrWorkspaceInfo(id: wsId, label: label),
          panes: [for (final agent in agents) HomeBoardPane(agent: agent)],
        );
        return SidebarNode(
          key: SidebarKeys.herdrWorkspace(host.id, wsId),
          kind: SidebarNodeKind.herdrWorkspace,
          machineId: host.id,
          label: label,
          target: HerdrWorkspaceTarget(host, workspace),
          children: [
            for (final pane in workspace.panes)
              SidebarNode(
                key: SidebarKeys.agentPane(host.id, wsId, null, pane.agent.id),
                kind: SidebarNodeKind.agentPane,
                machineId: host.id,
                label: pane.agent.name,
                dot: SidebarDot.of(pane.agent.state),
                agentKind: 'claude',
                target: AgentPaneTarget(host, workspace, pane),
              ),
          ],
        );
      }(),
  ],
);

void main() {
  // The companion prints its reply on one line.
  final decoded = jsonDecode(
    File('test/fixtures/sheprd/view-2026-10-31.json').readAsStringSync(),
  );
  final reply = jsonEncode(decoded);
  final view = (decoded as Map)['view'] as Map;
  final now = DateTime.fromMillisecondsSinceEpoch(
    (view['updated'] as int) * 1000,
  );
  // The companion stamps an agent's last change when it first sees it, so
  // after a companion restart every agent "changed" minutes ago.
  final restarted = now.subtract(const Duration(minutes: 2));
  AgentInfo agent(String pane, AgentAttentionState state) => AgentInfo(
    id: pane,
    name: 'agent $pane',
    state: state,
    pane: pane,
    workspace: pane.split(':').first,
    stateChangedAt: restarted,
  );
  const working = AgentAttentionState.working;
  const idle = AgentAttentionState.idle;

  final laptop = _host('h1', 'Laptop');
  final dev = _host('h2', 'Dev');
  List<SidebarNode> tree() => [
    _machine(laptop, {
      ('wH', 'Workout'): [agent('wH:p1', idle)],
      ('w3B', 'Projects'): [agent('w3B:p1', idle)],
      ('w3D', 'lf-seguros-web'): [agent('w3D:p1', idle)],
      ('wC', 'Follow up'): [agent('wC:p1', idle)],
      ('wW', 'Mail Marketing'): [agent('wW:p1', idle)],
    }),
    _machine(dev, {
      ('w44', 'lf-seguros-web'): [agent('w44:p1', working)],
      ('w2M', 'Calendar'): [agent('w2M:p1', working)],
      ('w4', 'Infrastructure'): [agent('w4:p4', working)],
      ('w47', 'Conductore'): [agent('w47:p1', working)],
      ('w1D', 'App Deployments'): [agent('w1D:p1', idle)],
      ('w2A', 'LitIntel'): [agent('w2A:p1', idle)],
      ('w3X', 'Projects'): [agent('w3X:p1', idle)],
      ('wY', 'Migrations'): [agent('wY:p1', idle)],
      ('wE', 'DTech'): [agent('wE:p1', idle)],
    }),
  ];

  late ThemeController theme;
  late ProjectLayoutController controller;

  setUp(() async {
    theme = ThemeController(InMemoryThemePreferences());
    await theme.load();
    controller = ProjectLayoutController(theme: theme, clock: () => now);
    await controller.setSheprdSync(true);
    // Only dev-central's relayed copy reached the phone.
    controller.applyViewReply(dev, reply);
  });
  tearDown(() => controller.dispose());

  /// What the Projects view lists: (project, workspace @ machine).
  List<(String, String)> shown() => [
    for (final group in controller.visibleGroups(
      controller.build(tree(), hosts: [laptop, dev]),
    ))
      for (final entry in controller.visibleEntries(group))
        (group.name, '${entry.node.label} @ ${entry.node.machineId}'),
  ];

  test("the active view lists exactly sheprd's active rows", () {
    expect(controller.mirroring, isTrue);
    expect(controller.activeOnly, isTrue, reason: 'layout.active_only');
    expect(shown(), [
      ('LF', 'lf-seguros-web @ h2'),
      ('TheCalendar', 'Calendar @ h2'),
      ('Infrastructure', 'Infrastructure @ h2'),
      ('Personal', 'Workout @ h1'),
      ('Other', 'App Deployments @ h2'),
      ('Other', 'Conductore @ h2'),
    ]);
  });

  test("rows carry sheprd's titles and active flags", () {
    final groups = controller.build(tree(), hosts: [laptop, dev]);
    final entries = {
      for (final group in groups)
        for (final entry in group.entries)
          '${entry.node.machineId}/${entry.node.label}': (group, entry),
    };
    String title(String key) {
      final (group, entry) = entries[key]!;
      return AgentRowText.ofEntry(
        entry,
        projectName: group.name,
        machine: '',
        now: now,
      ).title;
    }

    expect(title('h2/lf-seguros-web'), 'Multi-agent bug search and fix');
    expect(title('h2/Infrastructure'), 'Tailscale audit for coolify URLs');
    expect(title('h1/Workout'), 'Design full-body 3x weekly workout split');
    expect(title('h2/LitIntel'), 'Law firm product for Portuguese market');
    final active = {
      for (final MapEntry(:key, value: (_, entry)) in entries.entries)
        if (entry.active) key,
    };
    expect(active, {
      'h2/lf-seguros-web',
      'h2/Calendar',
      'h2/Infrastructure',
      'h2/Conductore',
      'h2/App Deployments',
      'h1/Workout',
    });
  });

  test('all agents: every row, the inactive ones faded', () async {
    await controller.setActiveOnly(false);
    final labels = [for (final (_, row) in shown()) row];
    expect(
      labels,
      hasLength(12),
      reason: 'DTech and Mail Marketing are hidden',
    );
    expect(labels, isNot(contains('DTech @ h2')));
  });

  test("a workspace's agents outside sheprd's active view are left out", () {
    // Two agents in one workspace: one in sheprd's active view, one idle
    // for days (not removed by hand).
    final groups = controller.build(
      [
        _machine(dev, {
          ('w44', 'lf-seguros-web'): [
            agent('w44:p1', working),
            agent('wE:p1', idle),
          ],
        }),
      ],
      hosts: [laptop, dev],
    );
    final entry = groups.expand((g) => g.entries).single;
    SidebarNode row(String pane) =>
        entry.agentRows.firstWhere((r) => r.label == 'agent $pane');
    expect(entry.active, isTrue);
    expect(controller.leftOutOfActive(entry, row('w44:p1')), isFalse);
    expect(controller.leftOutOfActive(entry, row('wE:p1')), isTrue);
  });
}
