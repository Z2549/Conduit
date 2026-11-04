import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/home_board_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import 'home_board_fakes.dart';

// CON-133: a machine uses any of the Herdr app, Herdr TUI and tmux.
void main() {
  group('tools of a saved machine', () {
    test('machines saved before the choice keep what they had', () {
      final host = buildHost('a');
      for (final (backend, tools) in [
        (HostBackend.herdr, {HostTool.herdr, HostTool.tmux}),
        (HostBackend.sheprd, {HostTool.herdr, HostTool.tmux}),
        (HostBackend.hc, {HostTool.herdrApp, HostTool.tmux}),
      ]) {
        final json = host.copyWith(backend: backend).toJson()..remove('tools');
        expect(SavedHost.fromJson(json).tools, tools);
      }
    });

    test('a choice survives saving, and sets the backend', () {
      final host = buildHost(
        'a',
      ).copyWith(tools: const {HostTool.herdrApp, HostTool.herdr});
      expect(host.backend, HostBackend.hc);
      final back = SavedHost.fromJson(host.toJson());
      expect(back.tools, {HostTool.herdrApp, HostTool.herdr});
      expect(back.backend, HostBackend.hc);
      final none = buildHost('a').copyWith(tools: const {});
      expect(SavedHost.fromJson(none.toJson()).tools, isEmpty);
    });
  });

  group('the board lists only what is ticked', () {
    late HerdrFakeRunner runner;
    late HomeBoardController board;

    setUp(() {
      runner = HerdrFakeRunner(tmuxSessions: TmuxFixtures.sessions);
      board = HomeBoardController(
        runnerFactory: (_) => runner,
        pollInterval: const Duration(days: 1),
      );
      addTearDown(board.dispose);
    });

    Future<HomeBoardState> load(Set<HostTool> tools) async {
      board
        ..setVisible(true)
        ..selectHost(
          buildHost(
            'a',
          ).copyWith(tools: tools, lastConnectedAt: DateTime.utc(2026)),
          connectedBefore: true,
        );
      await pumpEventQueue();
      return board.state;
    }

    bool ran(String word) => runner.commands.any((c) => c.contains(word));

    test('tmux only: no herdr, no hc, no notice about them', () async {
      final state = await load(const {HostTool.tmux});
      expect(state.tmuxSessions, isNotEmpty);
      expect(state.workspaces, isEmpty);
      expect(ran('herdr'), isFalse);
      expect(ran('exec hc '), isFalse);
    });

    test('Herdr app only: tmux is not asked', () async {
      final state = await load(const {HostTool.herdrApp});
      expect(state.onHc, isTrue);
      expect(state.tmuxSessions, isEmpty);
      expect(state.workspaces, isNotEmpty);
      expect(ran('tmux'), isFalse);
      expect(ran('herdr'), isFalse);
    });

    test('Herdr app and Herdr TUI together: both listed', () async {
      final state = await load(const {
        HostTool.herdrApp,
        HostTool.herdr,
        HostTool.tmux,
      });
      final ids = state.workspaces.map((w) => w.id);
      expect(ids, contains('w1'));
      expect(ids.any((id) => id.startsWith('wHc')), isTrue);
      expect(state.tmuxSessions, isNotEmpty);
    });

    test('one down keeps the other', () async {
      runner
        ..hcExitCode = 1
        ..hcStderr = 'core is down';
      final state = await load(const {HostTool.herdrApp, HostTool.herdr});
      expect(state.phase, HomeBoardPhase.ready);
      expect(state.workspaces.map((w) => w.id), contains('w1'));
    });
  });
}
