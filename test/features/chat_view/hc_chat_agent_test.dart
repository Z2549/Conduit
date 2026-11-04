import 'dart:convert';

import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_launcher.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
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
}
