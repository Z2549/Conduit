import 'dart:io';

import 'package:conduit/core/presentation/multiplexer_icon.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/agent_attention/domain/agent_kinds.dart';
import 'package:conduit/features/sessions/data/workspace_creator.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/domain/new_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

// CON-136: "New agent" on a Herdr app (hc) machine. Spaces belong to the
// app's window, so the phone finds the machine with the window open and
// runs `herdr-app do space.new` there, naming this machine as that
// window's hc names it.

/// The script a posixShellCommand runs, decoded from its octal escapes.
String _script(String command) => command.replaceAllMapped(
  RegExp(r'\\([0-7]{3})'),
  (match) => String.fromCharCode(int.parse(match[1]!, radix: 8)),
);

const _claude = KnownAgentKind('claude', 'Claude Code', 'claude');

AgentCommandResult _out(String stdout, {int exitCode = 0}) =>
    AgentCommandResult(stdout: stdout, stderr: '', exitCode: exitCode);

/// [NewWorkspaceCommands.herdrAppPrepare]'s output on development-central.
String _prepared(List<String> addresses, {String dir = '/root/Projects/app'}) {
  final terminals = [
    for (final a in addresses)
      '{"address":"$a","agent":"claude-code","cwd":"/root","state":"live"}',
  ].join(',');
  return '@@dir\n$dir\n'
      '@@status\n{"core":{"id":"38de","name":"development-central"}}\n'
      '@@ls\n{"machines":[{"name":"omarchy","state":"connected"}],'
      '"terminals":[$terminals]}\n';
}

String _ls(List<(String, String)> terminals) {
  final items = [
    for (final (a, cwd) in terminals)
      '{"address":"$a","agent":"claude-code","cwd":"$cwd","state":"live"}',
  ].join(',');
  return '{"machines":[],"terminals":[$items]}';
}

const _omarchyMachines =
    '{"machines":[{"id":"38de","name":"development-central",'
    '"state":"connected"}]}';

void main() {
  const request = NewWorkspaceRequest(
    kind: MultiplexerKind.herdr,
    herdrApp: true,
    name: 'api',
    folder: '~/Projects/app',
    agent: _claude,
    task: 'Look at the login bug',
  );

  WorkspaceCreator creator(ScriptedAgentCommandRunner runner) =>
      WorkspaceCreator(runner, appearPoll: Duration.zero);

  test('the window on the laptop: space.new there, naming this machine, '
      'and the new terminal opens', () async {
    final runner = ScriptedAgentCommandRunner([
      _out(_prepared(['t1', 'omarchy/t3'])),
      _out('@@hub omarchy\n$_omarchyMachines\n'),
      _out('{"ok":true}'),
      _out(_ls([('t1', '/root'), ('t2', '/root/Projects/app')])),
    ]);
    final target = await creator(runner).create(request);
    expect(target, const ConnectTarget.hc('t2', label: 'api'));
    expect(_script(runner.commands[1]), contains('omarchy'));
    final made = _script(runner.commands[2]);
    expect(made, contains('hc exec --on omarchy herdr-app do space.new'));
    expect(made, contains('--machine development-central'));
    expect(made, contains("--folder '/root/Projects/app'"));
    expect(made, contains('--argv \'["claude"]\''));
    expect(made, contains("--task 'Look at the login bug'"));
  });

  test(
    'the window on this machine: space.new here, on this computer',
    () async {
      final runner = ScriptedAgentCommandRunner([
        _out(_prepared(['t1'])),
        _out('@@local\n'),
        _out(''),
        _out(_ls([('t1', '/root')])),
        _out(_ls([('t1', '/root'), ('t5', '/root/Projects/app')])),
      ]);
      final target = await creator(runner).create(request);
      expect(target.name, 't5');
      expect(_script(runner.commands[2]), isNot(contains('hc exec')));
      expect(_script(runner.commands[2]), contains("--machine ''"));
    },
  );

  test('no agent: no argv and no first message', () async {
    final runner = ScriptedAgentCommandRunner([
      _out(_prepared(['t1'])),
      _out('@@local\n'),
      _out(''),
      _out(_ls([('t1', '/root'), ('t2', '/root/Projects/app')])),
    ]);
    await creator(runner).create(
      const NewWorkspaceRequest(
        kind: MultiplexerKind.herdr,
        herdrApp: true,
        name: '',
        task: 'ignored',
      ),
    );
    expect(_script(runner.commands[2]), isNot(contains('--argv')));
    expect(_script(runner.commands[2]), isNot(contains('--task')));
    // No name: the app names it after where its terminal is.
    expect(_script(runner.commands[2]), isNot(contains('--name')));
  });

  test('of several new terminals, the one in the folder', () async {
    final runner = ScriptedAgentCommandRunner([
      _out(_prepared(['t1'])),
      _out('@@local\n'),
      _out(''),
      _out(
        _ls([('t1', '/root'), ('t7', '/tmp'), ('t8', '/root/Projects/app')]),
      ),
    ]);
    expect((await creator(runner).create(request)).name, 't8');
  });

  test(
    "another agent's new terminal elsewhere is never taken for it",
    () async {
      final runner = ScriptedAgentCommandRunner([
        _out(_prepared(['t1'])),
        _out('@@local\n'),
        _out(''),
        _out(_ls([('t1', '/root'), ('t6', '/root/Projects')])),
        _out(
          _ls([('t1', '/root'), ('t6', '/root/Projects'), ('t7', '/srv/x')]),
        ),
        _out(
          _ls([
            ('t1', '/root'),
            ('t6', '/root/Projects'),
            ('t7', '/srv/x'),
            ('t8', '/root/Projects/app'),
          ]),
        ),
      ]);
      expect((await creator(runner).create(request)).name, 't8');
    },
  );

  test('disconnected machines are not asked; a login banner before the '
      'answer is skipped', () async {
    final runner = ScriptedAgentCommandRunner([
      _out(
        '@@dir\n/root/Projects/app\n'
        '@@status\n{"core":{"id":"38de","name":"dev"}}\n'
        '@@ls\n{"machines":[{"name":"gone","state":"disconnected"},'
        '{"name":"omarchy","state":"connected"}],"terminals":[]}\n',
      ),
      _out('Welcome to dev!\n@@hub omarchy\n$_omarchyMachines\n'),
      _out(''),
      _out(_ls([('t2', '/root/Projects/app')])),
    ]);
    final target = await creator(runner).create(request);
    expect(target.name, 't2');
    final probe = _script(runner.commands[1]);
    expect(probe, contains('omarchy'));
    expect(probe, isNot(contains('gone')));
  });

  test("hc's identity unknown: said, nothing made", () async {
    final runner = ScriptedAgentCommandRunner([
      _out(
        '@@dir\n/x\n@@status\n@@ls\n{"machines":[{"name":"omarchy"}],"terminals":[]}\n',
      ),
      _out('@@hub omarchy\n$_omarchyMachines\n'),
    ]);
    await expectLater(
      creator(runner).create(request),
      throwsA(
        isA<NewWorkspaceFailure>().having(
          (f) => f.message,
          'message',
          contains('hc server status'),
        ),
      ),
    );
    expect(runner.commands, hasLength(2));
  });

  test('no window anywhere: said, nothing made', () async {
    final runner = ScriptedAgentCommandRunner([
      _out(_prepared(['t1'])),
      _out('@@none\n'),
    ]);
    await expectLater(
      creator(runner).create(request),
      throwsA(
        isA<NewWorkspaceFailure>().having(
          (f) => f.message,
          'message',
          contains('not open'),
        ),
      ),
    );
    expect(runner.commands, hasLength(2));
  });

  test("the window's hc does not reach this machine: said", () async {
    final runner = ScriptedAgentCommandRunner([
      _out(_prepared(['t1'])),
      _out('@@hub omarchy\n{"machines":[]}\n'),
    ]);
    await expectLater(
      creator(runner).create(request),
      throwsA(
        isA<NewWorkspaceFailure>().having(
          (f) => f.message,
          'message',
          contains('hc machine add'),
        ),
      ),
    );
    expect(runner.commands, hasLength(2));
  });

  test("the app's refusal is shown", () async {
    final runner = ScriptedAgentCommandRunner([
      _out(_prepared(['t1'])),
      _out('@@local\n'),
      _out('{\n  "error": "unknown argument \\"task\\""\n}'),
    ]);
    await expectLater(
      creator(runner).create(request),
      throwsA(
        isA<NewWorkspaceFailure>().having(
          (f) => f.message,
          'message',
          'The Herdr app refused: unknown argument "task"',
        ),
      ),
    );
  });

  test('a missing folder is said before anything is made', () async {
    final runner = ScriptedAgentCommandRunner([
      const AgentCommandResult(
        stdout: '',
        stderr: 'No such folder: /root/nope',
        exitCode: NewWorkspaceCommands.missingFolderExit,
      ),
    ]);
    await expectLater(
      creator(runner).create(request),
      throwsA(isA<NewWorkspaceFailure>()),
    );
    expect(runner.commands, hasLength(1));
  });

  test('the terminal never shows up: said, so it is not made twice', () async {
    var now = DateTime(2026, 11, 10);
    final runner = ScriptedAgentCommandRunner([
      _out(_prepared(['t1'])),
      _out('@@local\n'),
      _out(''),
      _out(_ls([('t1', '/root')])),
    ]);
    final made = WorkspaceCreator(
      runner,
      appearPoll: Duration.zero,
      clock: () => now = now.add(const Duration(seconds: 6)),
    ).create(request);
    await expectLater(
      made,
      throwsA(
        isA<NewWorkspaceFailure>().having(
          (f) => f.message,
          'message',
          contains('pick it from the list'),
        ),
      ),
    );
  });

  // The scripts run for real under sh, against fake hc and herdr-app in a
  // temporary HOME with a clean environment (never the live ones): every
  // word arrives as typed, quotes and `$(...)` included.
  group('under sh', () {
    late Directory home;
    setUp(() {
      home = Directory.systemTemp.createTempSync('hc-new-agent');
      final bin = Directory('${home.path}/.local/bin')
        ..createSync(recursive: true);
      Directory('${home.path}/Projects/my app').createSync(recursive: true);
      void tool(String name, String body) {
        final file = File('${bin.path}/$name')..writeAsStringSync(body);
        Process.runSync('chmod', ['+x', file.path]);
      }

      tool('hc', r'''#!/bin/sh
case "$1" in
  server) echo '{"core":{"id":"38de","name":"development-central"}}' ;;
  ls)
    if [ -f "$HOME/made" ]; then
      echo '{"machines":[{"name":"omarchy"}],"terminals":[{"address":"t1","cwd":"/x","state":"live"},{"address":"t9","cwd":"'"$(cat "$HOME/made")"'","state":"live"}]}'
    else
      echo '{"machines":[{"name":"omarchy"}],"terminals":[{"address":"t1","cwd":"/x","state":"live"}]}'
    fi ;;
  exec)
    shift; shift; machine=$1; shift
    if [ "$1" = hc ]; then
      echo '{"machines":[{"id":"38de","name":"development-central"}]}'
    else
      HUB=$machine exec "$@"
    fi ;;
esac
''');
      tool('herdr-app', r'''#!/bin/sh
case "$1" in
  status) [ -n "$HUB" ] ;;
  do)
    printf '%s\n' "$HUB" "$@" > "$HOME/argv"
    while [ $# -gt 0 ]; do
      [ "$1" = --folder ] && printf '%s' "$2" > "$HOME/made"
      shift
    done
    echo '{"ok":true}' ;;
esac
''');
    });
    tearDown(() => home.deleteSync(recursive: true));

    test('found on the laptop, made there for this machine', () async {
      final runner = _ShellRunner(home.path);
      final target = await WorkspaceCreator(runner, appearPoll: Duration.zero)
          .create(
            const NewWorkspaceRequest(
              kind: MultiplexerKind.herdr,
              herdrApp: true,
              name: r"it's $(touch /tmp/x)",
              folder: '~/Projects/my app',
              agent: _claude,
              task: 'fix "login"; rm -rf /',
            ),
          );
      expect(target.name, 't9');
      final argv = File('${home.path}/argv').readAsLinesSync();
      expect(argv, [
        'omarchy',
        'do',
        'space.new',
        '--name',
        r"it's $(touch /tmp/x)",
        '--folder',
        '${home.path}/Projects/my app',
        '--machine',
        'development-central',
        '--argv',
        '["claude"]',
        '--task',
        'fix "login"; rm -rf /',
      ]);
    });
  });
}

/// Runs each command under sh with only [home] as HOME and a bare PATH.
class _ShellRunner implements AgentCommandRunner {
  _ShellRunner(this.home);

  final String home;

  @override
  Future<AgentCommandResult> run(
    String command, {
    required Duration timeout,
  }) async {
    final result = await Process.run(
      'sh',
      ['-c', command],
      environment: {'HOME': home, 'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: false,
    );
    return AgentCommandResult(
      stdout: result.stdout as String,
      stderr: result.stderr as String,
      exitCode: result.exitCode,
    );
  }

  @override
  Future<void> close() async {}
}
