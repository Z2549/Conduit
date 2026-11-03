import 'package:conduit/features/desktop_shell/domain/hc_documents.dart';
import 'package:conduit/features/desktop_shell/domain/project_tree.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_prefs.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

// CON-130: the Projects view of an hc machine, from `hc ls` and the Herdr
// app sidebar's `sheprd-view`.
void main() {
  HcTerminalInfo terminal(
    String address,
    String where, {
    String status = 'idle',
    String cwd = '/root/x',
  }) => HcTerminalInfo(
    address: address,
    agent: 'claude-code',
    cwd: cwd,
    status: status,
    where: where,
  );

  final terminals = [
    terminal('t1d', 'Calendar / 1', status: 'done'),
    terminal('t1m', 'lf-seguros-web / 1', status: 'working'),
    terminal('omarchy/t5', 'Follow up / 1'),
    terminal('omarchy/t12', 'Projects / 1'),
    terminal('omarchy/t16', 'Projects / 2'),
    terminal('t9', '', cwd: '/root/Projects/Barbusano'),
    const HcTerminalInfo(address: 't3', where: 'Shell / 1', live: false),
  ];

  test('spaces become workspaces, by `where`, else the folder', () {
    final spaces = HomeBoardController.hcWorkspaces(terminals);
    expect(spaces.map((w) => w.label), [
      'Calendar',
      'lf-seguros-web',
      'Follow up',
      'Projects',
      'Barbusano',
    ]);
    expect(spaces[3].panes.map((p) => p.agent.id), [
      'omarchy/t12',
      'omarchy/t16',
    ]);
    expect(
      spaces.first.id,
      HomeBoardController.hcWorkspaces(terminals).first.id,
    );
    expect(spaces.first.id, startsWith('wHc'));
    expect(spaces.first.summary, isNotNull);
  });

  test('the app layout groups them, keyed by space name on this machine', () {
    final view = HcSheprdView.fromJson({
      'v': 1,
      'projects': [
        {
          'name': 'Calendar',
          'members': ['development-central/Calendar'],
        },
        {
          'name': 'LF',
          'members': ['local/LF'],
          'match': ['lf-seguros'],
        },
        {
          'name': 'Follow',
          'members': ['local/Follow up#sp7', 'local/Projects'],
        },
      ],
      'hidden': ['development-central/Barbusano#sp9'],
      'density': 'compact',
    })!;
    final layout = view.toProjectLayout('Dev');
    expect(layout.groups.last.members, ['dev/Follow up', 'dev/Projects']);
    expect(layout.hidden, ['dev/Barbusano']);
    expect(layout.compact, isTrue);

    final host = buildHost('dev').copyWith(name: 'Dev');
    final tree = SidebarTreeBuilder.build([
      SidebarMachineInput(
        host: host,
        board: HomeBoardState(
          phase: HomeBoardPhase.ready,
          backend: HostBackend.hc,
          hcTerminals: terminals,
          workspaces: HomeBoardController.hcWorkspaces(terminals),
        ),
      ),
    ], const SidebarPrefs());
    final projects = ProjectTreeBuilder.build(tree, layout: layout);
    String labels(String name) => projects
        .firstWhere((p) => p.name == name)
        .members
        .map((n) => n.label)
        .join(',');
    expect(labels('Calendar'), 'Calendar');
    expect(labels('LF'), 'lf-seguros-web');
    expect(labels('Follow'), 'Follow up,Projects');
    final other = projects.firstWhere((p) => p.isOther);
    expect(other.entries.where((e) => e.hidden).map((e) => e.node.label), [
      'Barbusano',
    ]);
  });
}
