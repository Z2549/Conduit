import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/presentation/connect_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  AgentCommandResult ok(String stdout) =>
      AgentCommandResult(stdout: stdout, stderr: '', exitCode: 0);

  final tmux = ok('');
  final ls = ok(
    '{"hidden_finished":0,"terminals":[{"address":"t1","agent":"claude",'
    '"cwd":"/root/Conductore-Mobile","state":"live","status":"blocked",'
    '"turn":2},{"address":"t2","agent":"bash","cwd":"/root/Barbusano",'
    '"name":"shell","state":"live","turn":0}]}',
  );
  final docs = ok(
    '{"id":1,"jsonrpc":"2.0","result":{"version":2,"value":{"v":1,'
    '"projects":[{"name":"Conductore","short":"CO","members":[],'
    '"match":["conductore"]}],"marks":{}}}}\n'
    '{"id":2,"jsonrpc":"2.0","result":{"version":5,"value":{"v":1,'
    '"cards":{"t1/CON-1":{"id":"CON-1","terminal":"t1","title":"hc backend",'
    '"questions":[{"n":1,"text":"Ship?","state":"open"}]}}}}}\n',
  );
  final noDocs = ok(
    '{"id":1,"jsonrpc":"2.0","result":{"value":null,"version":0}}\n'
    '{"id":2,"jsonrpc":"2.0","result":{"value":null,"version":0}}\n',
  );

  Future<(ScriptedAgentCommandRunner, List<ConnectPickerResult>)> pump(
    WidgetTester tester,
    List<Object> script,
  ) async {
    final runner = ScriptedAgentCommandRunner(script);
    final picked = <ConnectPickerResult>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectPickerSheet(
            host: buildHost('h').copyWith(backend: HostBackend.hc),
            runner: runner,
            initialTab: ConnectPickerTab.hc,
            onPicked: picked.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (runner, picked);
  }

  testWidgets('lists hc terminals under sheprd projects and opens one', (
    tester,
  ) async {
    final (runner, picked) = await pump(tester, [tmux, ls, docs]);

    expect(find.text('Herdr app'), findsOneWidget);
    expect(runner.commands[1], contains('hc ls --json'));
    expect(runner.commands[2], contains('hc connect'));
    expect(runner.commands.any((c) => c.contains('herdr ')), isFalse);

    expect(find.text('CO · CONDUCTORE'), findsOneWidget);
    expect(find.text('OTHER'), findsOneWidget);
    expect(find.text('claude in Conductore-Mobile'), findsOneWidget);
    expect(find.textContaining('CON-1 hc backend'), findsOneWidget);
    expect(find.textContaining('1 question'), findsOneWidget);
    expect(find.text('Needs input'), findsOneWidget);

    await tester.tap(find.text('shell'));
    expect(picked.single.target, const ConnectTarget.hc('t2', label: 'shell'));
  });

  testWidgets('without sheprd documents the terminals are one list', (
    tester,
  ) async {
    await pump(tester, [tmux, ls, noDocs]);
    expect(find.text('OTHER'), findsNothing);
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('claude in Conductore-Mobile'), findsOneWidget);
  });

  testWidgets('reads the view from the hub: marked first, hidden folded', (
    tester,
  ) async {
    final remoteLs = ok(
      '{"hidden_finished":0,"terminals":[{"address":"t1","agent":"claude",'
      '"cwd":"/root/Conductore-Mobile","state":"live","turn":0},'
      '{"address":"t2","agent":"bash","cwd":"/root/Barbusano","name":"shell",'
      '"state":"live","turn":0},{"address":"omarchy/t5","agent":"claude",'
      '"cwd":"/home/a/Notes","name":"notes","state":"live","turn":0}]}',
    );
    final hubDocs = ok(
      '{"id":1,"jsonrpc":"2.0","result":{"version":3,"value":{"v":1,'
      '"projects":[],"hidden":["development-central/Barbusano"],'
      '"density":"compact","marks":{"marked":["t5"]}}}}\n'
      '{"id":2,"jsonrpc":"2.0","result":{"version":4,"value":{"v":1,'
      '"cards":{"t5/CON-9":{"id":"CON-9","terminal":"t5","title":"notes"}}}}}\n',
    );
    final (runner, _) = await pump(tester, [tmux, remoteLs, noDocs, hubDocs]);

    expect(runner.commands[3], contains('omarchy'));
    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .toList();
    expect(
      titles.indexOf('★ notes'),
      lessThan(titles.indexOf('claude in Conductore-Mobile')),
    );
    expect(find.text('CON-9 notes'), findsOneWidget, reason: 'compact');
    expect(find.text('shell'), findsNothing);
    expect(find.textContaining('HIDDEN 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hc-hidden-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('shell'), findsOneWidget);
  });

  testWidgets('a card question is answered from the actions sheet', (
    tester,
  ) async {
    final (runner, _) = await pump(tester, [tmux, ls, docs, ok('sent')]);
    await tester.tap(find.byKey(const ValueKey('target-tile-more')).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('CON-1 Q1: Ship?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hc-answer-CON-1-1-other')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('hc-answer-field')),
      'yes',
    );
    await tester.tap(find.text('Send').last);
    await tester.pumpAndSettle();

    expect(runner.commands.last, contains('cards stage t1 CON-1 1 yes'));
    expect(runner.commands.last, contains('cards send t1'));
    expect(find.text('→ yes (sent)'), findsOneWidget);
  });

  testWidgets('the actions list read, send and keys, and why the rest is off', (
    tester,
  ) async {
    final (runner, _) = await pump(tester, [
      tmux,
      ls,
      noDocs,
      ok('line one\nline two\n'),
    ]);
    await tester.tap(find.byKey(const ValueKey('target-tile-more')).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('hc-action-read')), findsOneWidget);
    expect(find.byKey(const ValueKey('hc-action-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('hc-key-ctrl+c')), findsOneWidget);
    final split = tester.widget<ListTile>(
      find.byKey(const ValueKey('hc-unsupported-splitPane')),
    );
    expect(split.enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('hc-action-read')));
    await tester.pumpAndSettle();
    expect(runner.commands.last, contains('hc read --lines 200 -- t1'));
    expect(find.textContaining('line two'), findsOneWidget);
  });

  // CON-137: a highlighted agent has the Herdr app's bar and tint.
  testWidgets('a highlighted agent has the bar', (tester) async {
    final highlighted = ok(
      '{"id":1,"jsonrpc":"2.0","result":{"version":2,"value":{"v":1,'
      '"projects":[],"marks":{"highlighted":["t2"]}}}}\n'
      '{"id":2,"jsonrpc":"2.0","result":{"value":null,"version":0}}\n',
    );
    await pump(tester, [tmux, ls, highlighted]);
    expect(find.byKey(const ValueKey('hc-highlight')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('hc-highlight')),
        matching: find.text('shell'),
      ),
      findsOneWidget,
    );
  });

  // CON-136: the Herdr app tab starts new agents too, not only attaches.
  testWidgets('New agent opens the Herdr app dialog with a first message', (
    tester,
  ) async {
    await pump(tester, [
      tmux,
      ls,
      noDocs,
      // The agents installed on the machine.
      ok('claude\n'),
    ]);
    await tester.tap(find.byKey(const ValueKey('hc-new-agent')));
    await tester.pumpAndSettle();
    expect(find.text('New agent in the Herdr app'), findsOneWidget);
    expect(find.text('Space name'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-workspace-task')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('new-workspace-agent-claude')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-workspace-task')), findsOneWidget);
  });
}
