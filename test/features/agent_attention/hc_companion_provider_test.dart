import 'package:conduit/features/agent_attention/data/hc_companion_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:conduit/features/sessions/presentation/session_grid_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

// CON-134: on the Herdr app, hc says who is there and in what state.
void main() {
  AgentInfo session(
    String id,
    String terminal, {
    List<PendingPermissionRequest> pending = const [],
  }) => AgentInfo(
    id: id,
    name: 'folder',
    state: AgentAttentionState.needsInput,
    pane: terminal,
    herdrServer: 'hc',
    lastMessage: 'Claude is waiting for your input',
    pendingRequests: pending,
  );

  HcTerminalInfo terminal(String address, String status, String where) =>
      HcTerminalInfo(
        address: address,
        agent: 'claude-code',
        status: status,
        where: where,
      );

  test('an idle Claude is idle, named after its space', () {
    final agents = HcCompanionProvider.merge(
      [session('s1', 't1')],
      [terminal('t1', 'idle', 'Calendar / 1')],
    );
    expect(agents.single.id, 's1');
    expect(agents.single.state, AgentAttentionState.idle);
    expect(agents.single.name, 'Calendar');
    expect(agents.single.lastMessage, isNotNull);
  });

  test('blocked needs you; a pending approval needs you whatever hc says', () {
    final blocked = HcCompanionProvider.merge(
      [session('s1', 't1')],
      [terminal('t1', 'blocked', 'A / 1')],
    );
    expect(blocked.single.state, AgentAttentionState.needsInput);
    final pending = HcCompanionProvider.merge(
      [
        session(
          's1',
          't1',
          pending: const [
            PendingPermissionRequest(id: 'r', toolName: 'Bash', summary: 'ls'),
          ],
        ),
      ],
      [terminal('t1', 'idle', 'A / 1')],
    );
    expect(pending.single.state, AgentAttentionState.needsInput);
  });

  test('a done terminal is not an ended session: Chat View can open', () {
    final done = HcCompanionProvider.merge(
      [session('s1', 't1')],
      [terminal('t1', 'done', 'A / 1')],
    ).single;
    expect(done.state, AgentAttentionState.finished);
    expect(done.ended, isFalse);
    const ended = AgentInfo(
      id: 's',
      name: 'x',
      state: AgentAttentionState.finished,
    );
    expect(ended.ended, isTrue);
  });

  test('other machines report for themselves; a terminal without a session '
      'is still listed', () {
    final agents = HcCompanionProvider.merge(const [], [
      terminal('t2', 'working', 'B / 1'),
      terminal('dev/t3', 'blocked', 'C / 1'),
    ]);
    expect(agents.map((a) => a.id), ['t2']);
  });

  test('sessions that left go, unless the machine uses their tool', () {
    const oldHerdr = AgentInfo(
      id: 'h',
      name: 'x',
      state: AgentAttentionState.needsInput,
      workspace: 'w1',
      tab: 'w1:t1',
      pane: 'w1:p1',
    );
    const inTmux = AgentInfo(
      id: 't',
      name: 'y',
      state: AgentAttentionState.idle,
      tab: 'main:1',
      pane: '%1',
    );
    const nowhere = AgentInfo(
      id: 'n',
      name: 'z',
      state: AgentAttentionState.needsInput,
    );
    final all = [oldHerdr, inTmux, nowhere];
    expect(HcCompanionProvider.merge(all, const []), isEmpty);
    expect(
      HcCompanionProvider.merge(all, const [], keepTmux: true).map((a) => a.id),
      ['t'],
    );
    expect(
      HcCompanionProvider.merge(
        all,
        const [],
        keepHerdr: true,
      ).map((a) => a.id),
      ['h'],
    );
  });

  test('an hc session shows its own agent, not the machine\'s worst', () {
    final status = AgentHostStatus(
      agents: [
        session('s1', 't1'),
        const AgentInfo(
          id: 's2',
          name: 'y',
          state: AgentAttentionState.idle,
          pane: 't2',
          herdrServer: 'hc',
        ),
      ],
    );
    expect(
      summarizeAgentState(
        status,
        const ConnectTarget.hc('t2').apply(buildHost('h')).id,
      ),
      AgentAttentionState.idle,
    );
  });
}
