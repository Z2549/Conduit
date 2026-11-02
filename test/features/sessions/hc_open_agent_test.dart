import 'package:conduit/features/agent_attention/data/hc_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/hosts/presentation/hosts_controller.dart';
import 'package:conduit/features/sessions/domain/connect_preferences.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/connect_picker_sheet.dart';
import 'package:conduit/features/sessions/presentation/session_connect_flow.dart';
import 'package:conduit/features/terminal/presentation/terminal_workspace_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';
import '../terminal/herdr/fake_herdr_runner.dart';

/// A notification or tile for an hc agent opens its terminal with
/// `hc attach`, the way the connect picker's Herdr app tab does.
void main() {
  late TerminalWorkspaceController workspace;
  late SessionConnectFlow flow;
  late List<FakeHerdrRunner> runners;
  final host = buildHost('h').copyWith(backend: HostBackend.hc);

  setUp(() {
    runners = [];
    workspace = TerminalWorkspaceController(NoNetworkTerminalRepository());
    flow = SessionConnectFlow(
      hostsController: HostsController(
        FakeHostsRepository()..persisted = [host],
      ),
      workspace: workspace,
      runnerFactory: (_) {
        final runner = FakeHerdrRunner(FakeHerdrRunner.panesResponse);
        runners.add(runner);
        return runner;
      },
      preferences: InMemoryConnectPreferencesRepository(),
    );
  });

  tearDown(() async {
    await flow.herdr.dispose();
    workspace.dispose();
  });

  Future<AgentInfo> hcAgent() async {
    final snapshot = await const HcAttentionProvider().fetchAgents(
      ScriptedAgentCommandRunner([
        const AgentCommandResult(
          stdout:
              '{"terminals":[{"address":"t7","agent":"claude","cwd":'
              '"/root/api","name":"reviewer","state":"live","status":'
              '"blocked","turn":2}]}',
          stderr: '',
          exitCode: 0,
        ),
      ]),
    );
    return snapshot.agents.single;
  }

  test('opens the hc terminal of an agent hc listed', () async {
    workspace.open(host);
    var requests = 0;
    flow.terminalRequests.addListener(() => requests += 1);

    final shown = await flow.openAgent(host, await hcAgent());

    expect(shown, isNotNull);
    expect(shown!.host.id, 'h#hc:t7');
    expect(shown.startupCommand, 'hc attach -- t7');
    expect(workspace.activeSession, shown);
    expect(requests, 1);
    expect(runners, isEmpty, reason: 'no herdr focus over hc');
  });

  test('reuses the tab already attached to that terminal', () async {
    final attached = workspace.open(
      const ConnectTarget.hc('t7').apply(host),
      startupCommand: const ConnectTarget.hc('t7').startupCommand,
    );
    workspace.open(host);

    final shown = await flow.openAgent(host, await hcAgent());

    expect(shown, attached);
    expect(workspace.activeSession, attached);
  });

  test('a remembered hc terminal opens the picker on the Herdr app tab', () {
    expect(
      SessionConnectFlow.initialTabFor(const ConnectTarget.hc('t7')),
      ConnectPickerTab.herdr,
    );
    expect(
      SessionConnectFlow.initialTabFor(
        const ConnectTarget.herdr(workspaceId: 'w1'),
      ),
      ConnectPickerTab.herdr,
    );
    expect(
      SessionConnectFlow.initialTabFor(const ConnectTarget.tmux('work')),
      ConnectPickerTab.tmux,
    );
    expect(SessionConnectFlow.initialTabFor(null), ConnectPickerTab.tmux);
    // Nothing remembered: an hc machine opens on its Herdr app tab.
    expect(
      SessionConnectFlow.initialTabFor(null, HostBackend.hc),
      ConnectPickerTab.herdr,
    );
    expect(
      SessionConnectFlow.initialTabFor(
        const ConnectTarget.tmux('work'),
        HostBackend.hc,
      ),
      ConnectPickerTab.tmux,
    );
  });
}
