import 'package:conduit/core/theme/theme_controller.dart';
import 'package:conduit/features/desktop_shell/domain/hc_documents.dart';
import 'package:conduit/features/desktop_shell/domain/project_layout.dart';
import 'package:conduit/features/desktop_shell/domain/project_tree.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_prefs.dart';
import 'package:conduit/features/desktop_shell/domain/sidebar_tree.dart';
import 'package:conduit/features/desktop_shell/presentation/project_layout_controller.dart';
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
    expect(layout.groups.last.members, [
      'dev/${hcSpaceWorkspaceId('sp7')}:Follow up',
      'dev/Projects',
    ]);
    expect(layout.hidden, ['dev/${hcSpaceWorkspaceId('sp9')}:Barbusano']);
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

  test('machines with their own board are left out of the spaces', () {
    final spaces = HomeBoardController.hcWorkspaces(
      terminals,
      skipMachines: const {'omarchy'},
    );
    expect(spaces.map((w) => w.label), [
      'Calendar',
      'lf-seguros-web',
      'Barbusano',
    ]);
  });

  // CON-135: André's phone put every space called "Projects" (on any
  // machine) in LF, the first project listing one, because the app's
  // `#<space id>` was dropped. hc's `terminal.list` gives each terminal
  // its space id, so same-named spaces stay apart.
  group('same-named spaces (CON-135)', () {
    HcTerminalInfo inSpace(String address, String where, String spaceId) =>
        HcTerminalInfo(
          address: address,
          agent: 'claude-code',
          cwd: '/root/Projects',
          status: 'done',
          where: where,
          spaceId: spaceId,
          title: 'task of $address',
        );
    final same = [
      inSpace('t24', 'Projects / 1', 'spe535'),
      inSpace('t27', 'Projects / 1', 'spd24a'),
      inSpace('omarchy/t12', 'Projects / 1', 'sp1d0c'),
      inSpace('omarchy/t13', 'Projects / 1', 'sp6224'),
      inSpace('t1m', 'Wave 3 / 1', 'specc5'),
      inSpace('t2d', 'lf-seguros-web / 1', 'sp1475'),
      inSpace('t2g', 'lf-seguros-web / 1', 'spa938'),
      inSpace('omarchy/t1j', '1M plan / 2', 'sp92ec'),
      inSpace('omarchy/t6', '1M plan / 1', 'sp92ec'),
    ];

    test('one workspace per space id, tabs of one space together', () {
      final spaces = HomeBoardController.hcWorkspaces(same);
      expect(spaces.map((w) => w.label), [
        'Projects',
        'Projects',
        'Projects',
        'Projects',
        'Wave 3',
        'lf-seguros-web',
        'lf-seguros-web',
        '1M plan',
      ]);
      expect(spaces.map((w) => w.id).toSet(), hasLength(8));
      expect(spaces.last.panes.map((p) => p.agent.id), [
        'omarchy/t1j',
        'omarchy/t6',
      ]);
      // Agent rows carry the terminal's title, as the app's sidebar does.
      expect(spaces.first.panes.single.title, 'task of t24');
    });

    test("members go to their own project, as in the app's sidebar", () {
      final view = HcSheprdView.fromJson({
        'v': 1,
        'projects': [
          {
            'name': 'LF',
            'match': ['lf-'],
            'members': [
              'local/Projects#sp6224',
              'development-central/lf-seguros-web#development-central/sp1475',
              'development-central/lf-seguros-web#development-central/spa938',
              'development-central/Wave 3',
            ],
          },
          {
            'name': 'Ops',
            'members': ['local/Projects#sp1d0c', 'local/1M plan#sp92ec'],
          },
          {
            'name': 'Shperd',
            'members': [
              'development-central/Projects#development-central/spe535',
            ],
          },
        ],
      })!;
      final host = buildHost('dev').copyWith(name: 'Dev');
      final tree = SidebarTreeBuilder.build([
        SidebarMachineInput(
          host: host,
          board: HomeBoardState(
            phase: HomeBoardPhase.ready,
            backend: HostBackend.hc,
            hcTerminals: same,
            workspaces: HomeBoardController.hcWorkspaces(same),
          ),
        ),
      ], const SidebarPrefs());
      final projects = ProjectTreeBuilder.build(
        tree,
        layout: view.toProjectLayout('Dev'),
      );
      List<String> agents(String name) => [
        for (final entry in projects.firstWhere((p) => p.name == name).entries)
          for (final row
              in entry.agentRows.isEmpty ? [entry.node] : entry.agentRows)
            row.label,
      ];
      expect(agents('LF')..sort(), [
        'task of omarchy/t13',
        'task of t1m',
        'task of t2d',
        'task of t2g',
      ]);
      expect(agents('Ops')..sort(), [
        'task of omarchy/t12',
        'task of omarchy/t1j',
        'task of omarchy/t6',
      ]);
      expect(agents('Shperd'), ['task of t24']);
      expect(agents(projects.firstWhere((p) => p.isOther).name), [
        'task of t27',
      ]);
    });

    test('an hc without space ids still matches members by name', () {
      final view = HcSheprdView.fromJson({
        'v': 1,
        'projects': [
          {
            'name': 'Ops',
            'members': ['local/Follow up#sp7'],
          },
        ],
      })!;
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
      final projects = ProjectTreeBuilder.build(
        tree,
        layout: view.toProjectLayout('Dev'),
      );
      expect(
        projects.firstWhere((p) => p.name == 'Ops').members.map((n) => n.label),
        ['Follow up'],
      );
    });

    test('an hc terminal open on the phone is its agent row, not a second '
        'row', () {
      final host = buildHost('dev').copyWith(name: 'Dev');
      final tree = SidebarTreeBuilder.build([
        SidebarMachineInput(
          host: host,
          board: HomeBoardState(
            phase: HomeBoardPhase.ready,
            backend: HostBackend.hc,
            hcTerminals: same,
            workspaces: HomeBoardController.hcWorkspaces(same),
          ),
          openSessions: const [
            SidebarOpenSession(
              sessionHostId: 'dev#hc:t2d',
              title: 'lf-seguros-web',
              hcTerminal: 't2d',
            ),
            SidebarOpenSession(
              sessionHostId: 'dev#hc:t99',
              title: 'a shell',
              hcTerminal: 't99',
            ),
          ],
        ),
      ], const SidebarPrefs());
      final machine = tree.single;
      final open = machine.children
          .where((n) => n.kind == SidebarNodeKind.openSession)
          .map((n) => n.label);
      // Only the terminal no agent row has stays a row of its own.
      expect(open, ['a shell']);
      final space = machine.children.firstWhere(
        (n) => n.kind == SidebarNodeKind.herdrWorkspace && n.openInApp,
      );
      expect(space.children.single.label, 'task of t2d');
      expect(space.children.single.openInApp, isTrue);
    });
  });

  group('review of CON-135', () {
    test('a space saved on the phone before CON-135 keeps its place', () {
      // Before, an hc space id was `wHc` + FNV-1a of its name.
      var hash = 0x811c9dc5;
      for (final unit in 'Projects'.codeUnits) {
        hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
      }
      final legacy = 'dev/wHc${hash.toRadixString(16)}:Projects';
      final now = 'dev/${hcSpaceWorkspaceId('spe535')}:Projects';
      expect(ProjectKeys.same(legacy, now), isTrue);
      // Two different app spaces stay apart.
      expect(
        ProjectKeys.same('dev/${hcSpaceWorkspaceId('sp1d0c')}:Projects', now),
        isFalse,
      );
    });

    test('a terminal in no app space is not grouped by name when others '
        'have ids', () {
      final list = [
        const HcTerminalInfo(
          address: 't24',
          status: 'done',
          where: 'Projects / 1',
          spaceId: 'spe535',
        ),
        const HcTerminalInfo(
          address: 't50',
          status: 'done',
          cwd: '/root/Projects',
        ),
      ];
      final spaces = HomeBoardController.hcWorkspaces(list);
      final loose = spaces.firstWhere((w) => w.panes.single.agent.id == 't50');
      expect(loose.label, 'Projects');
      expect(loose.id, isNot(startsWith('wHcn')));
      expect(
        ProjectKeys.same(
          'dev/${hcSpaceWorkspaceId('sp6224')}:Projects',
          'dev/${loose.id}:Projects',
        ),
        isFalse,
      );
    });

    test("a '#' in a space name is not an id", () {
      final view = HcSheprdView.fromJson({
        'v': 1,
        'projects': [
          {
            'name': 'Code',
            'members': ['local/C# app'],
          },
        ],
      })!;
      expect(view.toProjectLayout('Dev').groups.single.members, ['dev/C# app']);
    });

    test('projectOf goes by the space id when both sides have one', () {
      final view = HcSheprdView.fromJson({
        'v': 1,
        'projects': [
          {
            'name': 'LF',
            'members': ['local/Projects#sp6224'],
          },
          {
            'name': 'Ops',
            'members': ['local/Projects#sp1d0c'],
          },
        ],
      })!;
      HcTerminalInfo inSpace(String id) => HcTerminalInfo(
        address: 't1',
        cwd: '/home/a/Projects',
        status: 'done',
        spaceId: id,
      );
      expect(view.projectOf(inSpace('sp1d0c'))?.name, 'Ops');
      expect(view.projectOf(inSpace('sp6224'))?.name, 'LF');
      expect(view.projectOf(inSpace('spzzzz')), isNull);
    });
  });

  // CON-137: the Herdr app's highlight lives in `marks.highlighted`.
  group('highlights (CON-137)', () {
    test('read from marks.highlighted; missing means none', () {
      final view = HcSheprdView.fromJson({
        'v': 1,
        'marks': {
          'highlighted': ['t1d', 'omarchy/t5', '  ', 7],
        },
      })!;
      expect(view.isHighlighted(terminals[0]), isTrue);
      expect(view.isHighlighted(terminals[1]), isFalse);
      expect(view.isHighlighted(terminals[2]), isTrue);
      expect(view.highlightedAddresses, {'t1d', 'omarchy/t5'});
      expect(HcSheprdView.fromJson({'v': 1})!.highlighted, isEmpty);
    });

    test("read from the hub, its own agents get the hub's prefix and this "
        "host's lose theirs", () {
      final view = HcSheprdView.fromJson({
        'v': 1,
        'marks': {
          'highlighted': ['local/t3', 'development-central/t1d'],
        },
      })!.scoped(const HcKeyScope(hub: 'omarchy', machines: {'omarchy'}));
      expect(view.highlightedAddresses, {'omarchy/t3', 't1d'});
    });

    test('a key on a machine only the hub reaches lights nothing here; '
        "this host's own name is its bare address", () {
      final view =
          HcSheprdView.fromJson({
            'v': 1,
            'marks': {
              'highlighted': [
                'build/t3',
                'development-central/t1d',
                'local/t5',
              ],
            },
          })!.scoped(
            const HcKeyScope(
              hub: 'omarchy',
              machines: {'omarchy'},
              self: 'development-central',
            ),
          );
      expect(view.highlightedAddresses, {'t1d', 'omarchy/t5'});
      expect(
        view.isHighlighted(const HcTerminalInfo(address: 't3', where: 'x')),
        isFalse,
      );
    });

    test('_fetchHc scopes the first hub with a view (fromHubs)', () {
      final view = HcSheprdView.fromHubs(
        {
          1: null,
          2: {
            'v': 1,
            'marks': {
              'highlighted': ['local/t3', 'development-central/t1d'],
            },
          },
        },
        ['build', 'omarchy'],
        self: 'development-central',
      )!;
      expect(view.scope.hub, 'omarchy');
      expect(view.highlightedAddresses, {'omarchy/t3', 't1d'});
      expect(HcSheprdView.fromHubs({1: null}, ['omarchy']), isNull);
      expect(
        HcSheprdView.coreName(
          '{"core":{"id":"38de","name":"development-central"}}',
        ),
        'development-central',
      );
      expect(HcSheprdView.coreName('nope'), '');
    });

    test(
      'the controller keeps them per machine and matches agent rows',
      () async {
        final theme = ThemeController(InMemoryThemePreferences());
        await theme.load();
        final controller = ProjectLayoutController(theme: theme);
        addTearDown(controller.dispose);
        final host = buildHost('dev').copyWith(name: 'Dev');
        var notified = 0;
        controller.addListener(() => notified++);
        controller.applyHcView(
          host,
          HcSheprdView.fromJson({
            'v': 1,
            'marks': {
              'highlighted': ['t1m'],
            },
          }),
        );
        expect(controller.hcHighlighted('dev'), {'t1m'});
        expect(notified, 1);
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
        final agents = [
          for (final node in tree.single.descendantsAndSelf)
            if (node.kind == SidebarNodeKind.agentPane) node,
        ];
        expect([
          for (final a in agents)
            if (controller.isHighlighted(a)) a.label,
        ], hasLength(1));
        controller.applyHcView(host, null);
        expect(controller.hcHighlighted('dev'), isEmpty);
        expect(notified, 2);
      },
    );
  });
}
