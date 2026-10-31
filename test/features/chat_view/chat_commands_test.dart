import 'dart:convert';

import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/chat_view/data/conductore_chat_client.dart';
import 'package:conduit/features/chat_view/domain/chat_items.dart';
import 'package:conduit/features/chat_view/domain/chat_tool_activity.dart';
import 'package:conduit/features/chat_view/domain/chat_transcript.dart';
import 'package:conduit/features/chat_view/domain/chat_user_input.dart';
import 'package:conduit/features/chat_view/domain/slash_commands.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_controller.dart';
import 'package:conduit/features/chat_view/presentation/chat_view_page.dart';
import 'package:conduit/features/chat_view/presentation/widgets/chat_composer.dart';
import 'package:conduit/features/voice/domain/voice_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_fixtures.dart';

AgentCommandResult ok(String stdout) =>
    AgentCommandResult(stdout: stdout, stderr: '', exitCode: 0);

/// `commands` replies from [commands] (or "unknown command"), `transcript`
/// from [pages], `send` ok.
class CommandsHost implements AgentCommandRunner {
  CommandsHost({this.commands});

  final String? commands;
  final List<String> pages = [];
  final List<String> sent = [];
  int commandCalls = 0;
  var _offset = 0;

  @override
  Future<AgentCommandResult> run(
    String command, {
    required Duration timeout,
  }) async {
    if (command.contains(' commands ')) {
      commandCalls += 1;
      final reply = commands;
      if (reply == null) {
        return AgentCommandResult(
          stdout: jsonEncode({'error': 'unknown command commands'}),
          stderr: '',
          exitCode: 1,
        );
      }
      return ok(reply);
    }
    if (command.contains(' transcript ')) {
      if (pages.isEmpty) return ok(page([], offset: _offset));
      final reply = pages.removeAt(0);
      _offset = (jsonDecode(reply) as Map)['offset'] as int;
      return ok(reply);
    }
    final b64 = RegExp('--text-b64 ([A-Za-z0-9+/=]+)').firstMatch(command)![1]!;
    sent.add(utf8.decode(base64.decode(b64)));
    return ok('{"ok":true}');
  }

  @override
  Future<void> close() async {}
}

Map<String, Object?> systemLine(String uuid, String content) => {
  'type': 'system',
  'uuid': uuid,
  'parentUuid': null,
  'timestamp': '2026-09-25T10:00:00.000Z',
  'isSidechain': false,
  'subtype': 'local_command',
  'content': content,
};

List<ChatItem> build(List<Map<String, Object?>> entries) =>
    ChatItemBuilder.build(TranscriptParser.parsePage(page(entries)).entries);

const companionReply = '''
{"sessionId":"s-1","kind":"claude",
 "builtin":[{"name":"compact","description":"Compact the conversation"},
            {"name":"model","description":"Set the model","menu":true}],
 "custom":[{"name":"deploy","description":"Ship it","scope":"project","argumentHint":"<env>"},
           {"name":"frontend:component","description":"Make a component","scope":"personal"}],
 "skills":[{"name":"talkbawt","description":"Hand work over","scope":"personal"}]}
''';

void main() {
  group('slash command output (c)', () {
    test('stdout and stderr parse, without colour codes; caveat hidden', () {
      final parts = ChatUserInput.parse(
        '<local-command-stdout>Added rule \u001b[1mBash(ls)\u001b[22m'
        '</local-command-stdout>',
      );
      final out = parts.single as SlashOutputPart;
      expect(out.stdout, 'Added rule Bash(ls)');
      expect(out.stderr, '');
      expect(
        ChatUserInput.parse(
          '<local-command-caveat>The command below was run directly'
          '</local-command-caveat>',
        ),
        isEmpty,
      );
      // Cut by the host's cap: no closing tag.
      final cut =
          ChatUserInput.parse('<local-command-stdout>Context 41%').single
              as SlashOutputPart;
      expect(cut.stdout, 'Context 41%');
      final none =
          ChatUserInput.parse(
                '<local-command-stdout>(no content)</local-command-stdout>',
              ).single
              as SlashOutputPart;
      expect(none.stdout, '');
    });

    test('the output goes under its chip, as user or system lines', () {
      final items = build([
        userLine(
          'cv',
          '<local-command-caveat>Caveat</local-command-caveat>',
          meta: true,
        ),
        userLine(
          'c1',
          '<command-name>/model</command-name>\n'
              '<command-message>model</command-message>\n'
              '<command-args></command-args>',
        ),
        userLine(
          'o1',
          '<local-command-stdout>Set model to Opus</local-command-stdout>',
        ),
        systemLine(
          'c2',
          '<command-name>/cost</command-name>\n'
              '<command-message>cost</command-message>\n'
              '<command-args></command-args>',
        ),
        systemLine(
          'o2',
          '<local-command-stderr>Not available</local-command-stderr>',
        ),
        userLine('u1', 'thanks'),
        // A stray output (no command right before it) is dropped.
        userLine('o3', '<local-command-stdout>stray</local-command-stdout>'),
      ]);
      final users = items.whereType<ChatUserMessage>().toList();
      expect(users.map((u) => u.text), ['/model', '/cost', 'thanks']);
      expect(users[0].commandOutput, 'Set model to Opus');
      expect(users[0].commandFailed, isFalse);
      expect(users[1].commandOutput, 'Not available');
      expect(users[1].commandFailed, isTrue);
      expect(users[2].hasCommandOutput, isFalse);
    });

    testWidgets('the chip shows the output block', (tester) async {
      final host = CommandsHost()
        ..pages.add(
          page([
            userLine('c1', '<command-name>/context</command-name>'),
            userLine(
              'o1',
              '<local-command-stdout>Context Usage 41%</local-command-stdout>',
            ),
          ], offset: 10),
        );
      final controller = ChatViewController(
        runner: host,
        sessionId: 's-1',
        pollInterval: const Duration(days: 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatViewPage(controller: controller, onOpenTerminal: () {}),
        ),
      );
      await tester.pump();
      await tester.pump();
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      expect(find.byKey(const ValueKey('slash-command-chip')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('slash-command-output')),
          matching: find.textContaining('Context Usage 41%'),
        ),
        findsOneWidget,
      );
    });
  });

  group('a ! command sent from the phone (d)', () {
    test('arrange keeps a shown item out of the tool group', () {
      final a = ChatToolCall(
        'b1',
        name: 'Bash',
        input: {},
        kind: ChatToolKind.bash,
        result: const ChatToolResult(content: 'ok', isError: false),
      );
      final b = ChatToolCall(
        'b2',
        name: 'Bash',
        input: {},
        kind: ChatToolKind.bash,
        result: const ChatToolResult(content: 'ok', isError: false),
      );
      const shell = ChatShellCommand('s1', command: 'ls', stdout: 'a');
      List<String> shape(List<ChatThreadEntry> entries) => [
        for (final e in entries)
          switch (e) {
            ChatItemEntry(:final item) => item.id,
            final ChatToolGroup g => 'group(${g.items.length})',
          },
      ];
      expect(
        shape(ChatToolActivity.arrange([a, b, shell], ToolActivity.collapsed)),
        ['group(3)'],
      );
      expect(
        shape(
          ChatToolActivity.arrange(
            [a, b, shell],
            ToolActivity.collapsed,
            shown: {'s1'},
          ),
        ),
        ['group(2)', 's1'],
      );
      expect(
        shape(
          ChatToolActivity.arrange(
            [a, shell],
            ToolActivity.hidden,
            shown: {'s1'},
          ),
        ),
        ['s1'],
      );
    });

    testWidgets('its result card shows open, outside the collapsed group', (
      tester,
    ) async {
      final host = CommandsHost()
        ..pages.add(
          page([
            userLine('u0', 'check'),
            assistantLine('a0', [
              toolUse('t1', 'Bash', {'command': 'pwd'}),
              toolUse('t2', 'Bash', {'command': 'id'}),
            ]),
            userLine('r0', [toolResult('t1', '/w'), toolResult('t2', 'root')]),
          ], offset: 10),
        );
      final controller = ChatViewController(
        runner: host,
        sessionId: 's-1',
        pollInterval: const Duration(days: 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChatViewPage(controller: controller, onOpenTerminal: () {}),
        ),
      );
      await tester.pump();
      await tester.pump();
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        '!ls',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(host.sent, ['!ls']);
      host.pages.add(
        page([
          userLine('s1', '<bash-input>ls</bash-input>'),
          userLine(
            's2',
            '<bash-stdout>README.md</bash-stdout><bash-stderr></bash-stderr>',
          ),
        ], offset: 20),
      );
      await controller.refresh();
      await tester.pump();
      await tester.pump();
      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('You ran'), findsOneWidget);
    });
  });

  group('the "/" list (a, b)', () {
    test('parses the companion reply; custom and skills first', () {
      final list = SlashCommandList.parse(companionReply);
      expect(list.commands.map((c) => c.name), [
        'deploy',
        'frontend:component',
        'talkbawt',
        'compact',
        'model',
      ]);
      expect(list.commands.first.argumentHint, '<env>');
      expect(list.commands.first.project, isTrue);
      expect(list.commands[2].source, SlashCommandSource.skill);
      expect(list.commands.last.menu, isTrue);
      expect(() => SlashCommandList.parse('[]'), throwsFormatException);
    });

    test('query and filter', () {
      expect(SlashCommandList.queryOf('/co'), 'co');
      expect(SlashCommandList.queryOf('/'), '');
      expect(SlashCommandList.queryOf('/compact now'), isNull);
      expect(SlashCommandList.queryOf('hello /co'), isNull);
      final list = SlashCommandList.parse(companionReply);
      expect(list.filter('comp').map((c) => c.name), [
        'frontend:component',
        'compact',
      ]);
      expect(list.filter('ship').map((c) => c.name), ['deploy']);
      expect(list.filter('').length, 5);
    });

    test('the controller asks the companion once, then reuses it', () async {
      final host = CommandsHost(commands: companionReply);
      var now = DateTime.utc(2026, 10, 31, 20);
      final controller = ChatViewController(
        runner: host,
        sessionId: 's-1',
        pollInterval: const Duration(days: 1),
        clock: () => now,
      );
      addTearDown(controller.dispose);
      final first = await controller.slashCommands(claude: true, listed: true);
      expect(first.commands, hasLength(5));
      await controller.slashCommands(claude: true, listed: true);
      expect(host.commandCalls, 1);
      now = now.add(ChatViewController.commandsTtl);
      await controller.slashCommands(claude: true, listed: true);
      expect(host.commandCalls, 2);
      final other = await controller.slashCommands(claude: false, listed: true);
      expect(other.commands, isEmpty);
    });

    test('an older companion falls back to the built-in list', () async {
      final host = CommandsHost();
      final controller = ChatViewController(
        runner: host,
        sessionId: 's-1',
        pollInterval: const Duration(days: 1),
      );
      addTearDown(controller.dispose);
      expect(
        await controller.slashCommands(claude: true, listed: true),
        same(SlashCommandList.claudeBuiltins),
      );
      expect(host.commandCalls, 1);
      // A failure is not asked again right away.
      await controller.slashCommands(claude: true, listed: true);
      expect(host.commandCalls, 1);
      expect(
        await controller.slashCommands(claude: true, listed: false),
        same(SlashCommandList.claudeBuiltins),
      );
      expect(host.commandCalls, 1);
      await expectLater(
        ConductoreChatClient(host).commands('s-1'),
        throwsA(isA<ChatUnsupported>()),
      );
    });

    Future<TextEditingController> pumpComposer(
      WidgetTester tester, {
      Future<SlashCommandList> Function()? load,
    }) async {
      final text = TextEditingController();
      addTearDown(text.dispose);
      tester.view
        ..physicalSize = const Size(360 * 3, 720 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatComposer(
                textController: text,
                onSend: (_) async {},
                onInterrupt: () async {},
                loadCommands:
                    load ?? () async => SlashCommandList.parse(companionReply),
              ),
            ),
          ),
        ),
      );
      return text;
    }

    testWidgets('typing / lists commands; picking one fills the field', (
      tester,
    ) async {
      final text = await pumpComposer(tester);
      final field = find.byKey(const ValueKey('chat-composer-field'));
      expect(
        find.byKey(const ValueKey('chat-command-suggestions')),
        findsNothing,
      );
      await tester.enterText(field, '/dep');
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('chat-command-suggestions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('slash-suggestion-deploy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('slash-suggestion-compact')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('slash-suggestion-deploy')));
      await tester.pump();
      expect(text.text, '/deploy ');
      // Past the name: the list closes.
      expect(
        find.byKey(const ValueKey('chat-command-suggestions')),
        findsNothing,
      );
    });

    testWidgets('the / menu starts a command and toggles the shell !', (
      tester,
    ) async {
      final text = await pumpComposer(tester);
      final menu = find.byKey(const ValueKey('chat-commands-menu'));
      // Inside the field: the row keeps its controls (no new button).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chat-composer-field')),
          matching: menu,
        ),
        findsOneWidget,
      );
      text.text = 'git status';
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-commands-shell')));
      await tester.pumpAndSettle();
      expect(text.text, '!git status');
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-commands-shell')));
      await tester.pumpAndSettle();
      expect(text.text, 'git status');

      // A path keeps its slash; a picked command loses it.
      for (final (before, after) in [
        ('/tmp/x/cleanup.sh', '!/tmp/x/cleanup.sh'),
        ('/deploy prod', '!deploy prod'),
      ]) {
        text.text = before;
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-commands-shell')));
        await tester.pumpAndSettle();
        expect(text.text, after);
      }

      text.text = '';
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-commands-slash')));
      await tester.pumpAndSettle();
      expect(text.text, '/');
      expect(
        find.byKey(const ValueKey('chat-command-suggestions')),
        findsOneWidget,
      );
    });

    testWidgets('no loader: no menu and no list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatComposer(onSend: (_) async {}, onInterrupt: () async {}),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('chat-commands-menu')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        '/',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('chat-command-suggestions')),
        findsNothing,
      );
    });
  });
}
