import 'dart:convert';

import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_launcher.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/session_navigation/domain/session_view_preferences.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

// CON-132: Chat View on an agent in a Herdr app terminal.
void main() {
  AgentInfo agent(String session, String terminal) =>
      ConductoreHostAttentionProvider.parseSnapshot(
        jsonEncode({
          'version': 1,
          'agents': [
            {
              'sessionId': session,
              'kind': 'claude',
              'cwd': '/root/x',
              'state': 'waiting_input',
              'hc': {'terminal': terminal},
            },
          ],
        }),
      ).agents.single;

  test('the companion reports the terminal as the agent\'s pane', () {
    final parsed = agent('s1', 't7');
    expect(parsed.id, 's1');
    expect(parsed.pane, 't7');
    expect(parsed.herdrServer, 'hc');
    expect(parsed.workspace, isNull);
  });

  test('an hc session finds the agent in its terminal, nothing else', () {
    final agents = [agent('s1', 't7'), agent('s2', 't8')];
    SavedHost on(String address) =>
        ConnectTarget.hc(address).apply(buildHost('a'));
    final match = resolveChatAgent(on('t8'), agents);
    expect((match as ChatAgentMatched).agent.id, 's2');
    // A terminal on another machine: its agent is not on this companion.
    final elsewhere = resolveChatAgent(on('dev/t8'), agents);
    expect(elsewhere, isA<ChatAgentAmbiguous>());
    expect((elsewhere as ChatAgentAmbiguous).elsewhere, isTrue);
  });

  test('a terminal of another machine has its chat on that machine', () {
    final hub = buildHost('hub').copyWith(name: 'omarchy');
    final dev = buildHost('dev').copyWith(name: 'development-central');
    SavedHost on(String address) => ConnectTarget.hc(address).apply(hub);

    expect(hcChatHost(on('t5'), [hub, dev])!.id, on('t5').id);
    final owner = hcChatHost(on('development-central/t1y'), [hub, dev])!;
    expect(baseHostId(owner.id), 'dev');
    expect(ConnectTarget.fromSessionHostId(owner.id)!.name, 't1y');
    expect(hcChatHost(on('elsewhere/t1'), [hub, dev]), isNull);
    expect(hcChatHost(hub, [hub, dev]), hub);
    // And it finds the agent there.
    final match = resolveChatAgent(owner, [agent('s9', 't1y')]);
    expect((match as ChatAgentMatched).agent.id, 's9');
  });

  test('a terminal with no session is not offered for chat', () {
    const bare = AgentInfo(
      id: 't5',
      name: 'x',
      state: AgentAttentionState.needsInput,
      pane: 't5',
      herdrServer: 'hc',
      kind: 'claude-code',
    );
    expect(bare.hcOnly, isTrue);
    expect(agent('s1', 't5').hcOnly, isFalse);
    expect(supportsChatView(bare), isFalse);
    expect(
      resolveChatAgent(
        const ConnectTarget.hc('t5').apply(buildHost('a')),
        const [bare],
      ),
      isA<ChatAgentNone>(),
    );
  });
}
