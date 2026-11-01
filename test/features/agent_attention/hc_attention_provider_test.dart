import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/hc_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  const ls = AgentCommandResult(
    stdout:
        '{"hidden_finished":0,"terminals":[{"address":"t1","agent":"cat",'
        '"cwd":"/root","state":"live","turn":0},{"address":"t2","agent":'
        '"claude","cwd":"/root/api","name":"reviewer","state":"live",'
        '"status":"blocked","turn":3},{"address":"t3","agent":"codex",'
        '"cwd":"/root/web","state":"live","status":"working","turn":1},'
        '{"address":"t4","agent":"claude","cwd":"/root/old","state":'
        '"finished","status":"done","turn":5}]}',
    stderr: '',
    exitCode: 0,
  );

  group('HcAttentionProvider', () {
    test('only live terminals that report a status are agents', () async {
      final snapshot = await const HcAttentionProvider().fetchAgents(
        ScriptedAgentCommandRunner([ls]),
      );
      expect(snapshot.agents.map((a) => a.id), ['t2', 't3']);
      final reviewer = snapshot.agents.first;
      expect(reviewer.name, 'reviewer');
      expect(reviewer.kind, 'claude');
      expect(reviewer.state, AgentAttentionState.needsInput);
      expect(reviewer.stateSequence, 3);
      expect(reviewer.pane, isNull, reason: 'no herdr pane to focus');
      expect(snapshot.agents.last.state, AgentAttentionState.working);
    });

    test('maps hc status words', () {
      expect(HcAttentionProvider.stateOf('done'), AgentAttentionState.finished);
      expect(HcAttentionProvider.stateOf('idle'), AgentAttentionState.idle);
      expect(HcAttentionProvider.stateOf('error'), AgentAttentionState.blocked);
      expect(
        HcAttentionProvider.stateOf('thinking'),
        AgentAttentionState.unknown,
      );
    });

    test('a missing hc stops monitoring', () {
      expect(
        const HcAttentionProvider().fetchAgents(
          ScriptedAgentCommandRunner([
            const AgentCommandResult(
              stdout: '',
              stderr: 'sh: 1: exec: hc: not found',
              exitCode: 127,
            ),
          ]),
        ),
        throwsA(isA<AgentProviderUnavailable>()),
      );
    });

    test('has no focus command', () {
      expect(
        const HcAttentionProvider().focusCommand(
          const AgentInfo(
            id: 't2',
            name: 'reviewer',
            state: AgentAttentionState.working,
          ),
        ),
        isNull,
      );
    });
  });

  group('provider selection by backend', () {
    (
      TerminalWorkspaceController,
      AgentAttentionController,
      ScriptedAgentCommandRunner,
    )
    build(List<Object> script) {
      final workspace = TerminalWorkspaceController(FreshTerminalRepository());
      final runner = ScriptedAgentCommandRunner(script);
      final controller = AgentAttentionController(
        workspace: workspace,
        runnerFactory: (_) => runner,
        provider: const HerdrAttentionProvider(),
        companionProvider: const ConductoreHostAttentionProvider(),
        pollInterval: const Duration(days: 1),
        watchRestartDelay: Duration.zero,
      );
      controller.setLongPoll(false);
      addTearDown(controller.dispose);
      addTearDown(workspace.dispose);
      return (workspace, controller, runner);
    }

    SavedHost host(HostBackend backend, {AgentMonitorKind? monitor}) =>
        buildHost('h').copyWith(
          agentAttentionEnabled: true,
          backend: backend,
          agentMonitor: monitor,
        );

    test('hc reads hc ls without probing the companion', () async {
      final (workspace, controller, runner) = build([ls]);
      await workspace.open(host(HostBackend.hc)).connect();
      await pumpEventQueue();

      expect(controller.providerFor('h').id, 'hc');
      expect(runner.commands.single, contains('hc ls --json'));
      expect(controller.statusFor('h')?.agents, hasLength(2));
    });

    test('an explicit companion choice still wins on hc', () async {
      final (workspace, controller, _) = build([
        const AgentCommandResult(
          stdout: '{"version":1,"seq":1,"agents":[]}',
          stderr: '',
          exitCode: 0,
        ),
      ]);
      await workspace
          .open(host(HostBackend.hc, monitor: AgentMonitorKind.companion))
          .connect();
      await pumpEventQueue();
      expect(controller.providerFor('h').id, 'conductore');
    });

    test('sheprd keeps the herdr CLI', () async {
      final (workspace, controller, _) = build([
        const AgentCommandResult(stdout: '[]', stderr: '', exitCode: 0),
      ]);
      await workspace
          .open(host(HostBackend.sheprd, monitor: AgentMonitorKind.herdr))
          .connect();
      await pumpEventQueue();
      expect(controller.providerFor('h').id, 'herdr');
    });
  });
}
