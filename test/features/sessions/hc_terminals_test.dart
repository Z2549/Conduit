import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_doubles.dart';

void main() {
  // Captured from hc 0.1.16 on dev, with one status added the way hc
  // reports it for an agent.
  const lsOutput =
      '{"hidden_finished":0,"terminals":[{"address":"t1","agent":"cat",'
      '"cwd":"/root/Projects","name":"cards-e2e","state":"live","turn":0},'
      '{"address":"t2","agent":"claude","cwd":"/root/Projects/'
      'Conductore-Mobile","state":"live","status":"blocked","turn":4},'
      '{"address":"dev/t9","agent":"codex","cwd":"/srv/api","name":"",'
      '"state":"finished","status":{"state":"done","app":"codex"},'
      '"turn":2}]}';

  group('HcListing.parseTerminals', () {
    test('reads hc ls --json', () {
      final terminals = HcListing.parseTerminals(lsOutput);
      expect(terminals.map((t) => t.address), ['t1', 't2', 'dev/t9']);

      final cat = terminals[0];
      expect(cat.displayLabel, 'cards-e2e');
      expect(cat.status, isEmpty, reason: 'plain programs report none');
      expect(cat.live, isTrue);
      expect(cat.machine, isEmpty);

      final claude = terminals[1];
      expect(claude.displayLabel, 'claude in Conductore-Mobile');
      expect(claude.status, 'blocked');
      expect(claude.turn, 4);

      final remote = terminals[2];
      expect(remote.machine, 'dev');
      expect(remote.live, isFalse);
      expect(remote.status, 'done', reason: 'the record form of status');
      expect(remote.displayLabel, 'codex in api');
    });

    test('accepts a bare array and the hc connect result envelope', () {
      expect(
        HcListing.parseTerminals('[{"address":"t3","agent":"bash"}]').single,
        const HcTerminalInfo(address: 't3', agent: 'bash'),
      );
      expect(
        HcListing.parseTerminals(
          '{"jsonrpc":"2.0","id":1,"result":{"terminals":[{"address":"t4",'
          '"foreground":{"name":"vim"}}]}}',
        ).single.agent,
        'vim',
      );
    });

    test('skips entries without an address, empty output is no terminals', () {
      expect(HcListing.parseTerminals('[{"name":"x"}, 3]'), isEmpty);
      expect(HcListing.parseTerminals('  '), isEmpty);
    });

    test('rejects output that is not a terminal list', () {
      expect(
        () => HcListing.parseTerminals('nope'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => HcListing.parseTerminals('{"something":"else"}'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HcListing.interpret', () {
    test('a missing hc is "not installed"', () {
      expect(
        HcListing.interpret(
          const AgentCommandResult(
            stdout: '',
            stderr: 'sh: 1: exec: hc: not found',
            exitCode: 127,
          ),
        ),
        isA<RemoteListingNotInstalled<HcTerminalInfo>>(),
      );
    });

    test('an hc error is shown by its message', () {
      final listing = HcListing.interpret(
        const AgentCommandResult(
          stdout: '',
          stderr:
              '{"error":{"kind":"core_unreachable","message":"no core '
              'answered","hint":"hc server start"}}',
          exitCode: 1,
        ),
      );
      expect(
        (listing as RemoteListingFailed<HcTerminalInfo>).message,
        'no core answered',
      );
    });

    test('a list is available', () {
      final listing = HcListing.interpret(
        const AgentCommandResult(stdout: lsOutput, stderr: '', exitCode: 0),
      );
      expect(
        (listing as RemoteListingAvailable<HcTerminalInfo>).items,
        hasLength(3),
      );
    });
  });

  test('errorMessage words the exit codes a phone user can act on', () {
    expect(HcListing.errorMessage('', 9), contains('waiting on a decision'));
    expect(HcListing.errorMessage('', 3), 'That terminal is gone.');
    expect(HcListing.errorMessage('', 11), 'That terminal has finished.');
    expect(HcListing.errorMessage('boom', 1), 'boom');
    expect(HcListing.errorMessage('', 1), 'hc exited with 1.');
  });

  test('parseDocAnswers keeps each answer by id, absent docs as null', () {
    final answers = HcListing.parseDocAnswers(
      '{"id":1,"jsonrpc":"2.0","result":{"value":{"v":1},"version":3}}\n'
      'garbage\n'
      '{"id":2,"jsonrpc":"2.0","result":{"value":null,"version":0}}\n'
      '{"id":3,"jsonrpc":"2.0","error":{"code":-1,"message":"x"}}\n',
    );
    expect(answers, {
      1: {'v': 1},
      2: null,
    });
  });

  group('HcCommands', () {
    test('quote what they pass to hc', () {
      expect(HcCommands.list, contains('exec hc ls --json'));
      expect(
        HcCommands.read('t2', lines: 50),
        contains('hc read --lines 50 -- t2'),
      );
      final send = HcCommands.send('dev/t7', "it's done; rm -rf /");
      expect(send, contains('hc send'));
      expect(send, isNot(contains("it's done; rm")));
      final keys = HcCommands.keys('t2', ['ctrl+c', 'esc']);
      expect(keys, contains('hc keys -- t2 '));
      expect(keys, contains('ctrl+c'));
      expect(keys, contains('esc'));
    });

    test('text that looks like a flag is typed, not parsed by hc', () async {
      // `hc send t7 -h` prints help and exits 0, so the phone would say
      // "Sent." with nothing typed; `--` must end hc's options first. The
      // commands run through sh with hc swapped for printf, which prints
      // the argv hc would get.
      Future<List<String>> argv(String command) async {
        final printing = command.replaceFirst(
          'exec hc ',
          r'exec printf "%s\n" ',
        );
        final result = await Process.run('sh', ['-c', printing]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return const LineSplitter().convert(result.stdout as String);
      }

      expect(await argv(HcCommands.send('t7', '-h')), [
        'send',
        '--',
        't7',
        '-h',
      ]);
      expect(await argv(HcCommands.send('t7', '- fix tests')), [
        'send',
        '--',
        't7',
        '- fix tests',
      ]);
      expect(await argv(HcCommands.keys('-odd', ['enter', 'ctrl+c'])), [
        'keys',
        '--',
        '-odd',
        'enter',
        'ctrl+c',
      ]);
      expect(await argv(HcCommands.read('-odd', lines: 5)), [
        'read',
        '--lines',
        '5',
        '--',
        '-odd',
      ]);
    });

    test('docGet sends one doc.get per name over hc connect', () {
      final command = HcCommands.docGet(['sheprd-view', 'sheprd-cards']);
      expect(command, contains('hc connect'));
      expect(command, contains('doc.get'));
      expect(command, contains('sheprd-view'));
      expect(command, contains('sheprd-cards'));
    });

    test('answerCard stages and sends on the agent\'s own machine', () {
      final here = HcCommands.answerCard('t7', 'SHE-12', 2, 'no, wait');
      expect(here, contains('cards stage t7 SHE-12 2'));
      expect(here, contains('cards send t7'));
      expect(here, isNot(contains('exec --on')));
      final there = HcCommands.answerCard('omarchy/t5', 'SHE-12', 1, 'yes');
      expect(
        there,
        contains('hc exec --on omarchy cards stage t5 SHE-12 1 yes'),
      );
      expect(there, contains('hc exec --on omarchy cards send t5'));
    });

    test('the probe suggests hc only when herdr is missing', () {
      expect(HcCommands.suggestFromProbe('hc\n'), HostBackend.hc);
      expect(HcCommands.suggestFromProbe('hc\nherdr\n'), HostBackend.herdr);
      expect(HcCommands.suggestFromProbe('herdr\n'), HostBackend.herdr);
      expect(HcCommands.suggestFromProbe(''), HostBackend.herdr);
    });
  });

  group('backend selection', () {
    test('a host without the setting stays on herdr', () {
      expect(HostBackend.parse(null), HostBackend.herdr);
      expect(HostBackend.parse('tmux'), HostBackend.herdr);
      final legacy = SavedHost.fromJson(
        buildHost('h').toJson()..remove('backend'),
      );
      expect(legacy.backend, HostBackend.herdr);
    });

    test('the setting survives a save', () {
      final host = buildHost('h').copyWith(backend: HostBackend.hc);
      expect(SavedHost.fromJson(host.toJson()).backend, HostBackend.hc);
      expect(
        SavedHost.fromJson(
          host.copyWith(backend: HostBackend.sheprd).toJson(),
        ).backend,
        HostBackend.sheprd,
      );
    });
  });

  group('unsupported actions', () {
    test('herdr and sheprd support every action', () {
      for (final backend in [HostBackend.herdr, HostBackend.sheprd]) {
        expect(unsupportedActions(backend), isEmpty);
      }
    });

    test('hc keeps list, read, send, keys and attach', () {
      for (final action in [
        MultiplexerAction.list,
        MultiplexerAction.read,
        MultiplexerAction.send,
        MultiplexerAction.keys,
        MultiplexerAction.attach,
      ]) {
        expect(unsupportedReason(HostBackend.hc, action), isNull);
      }
    });

    test('hc leaves out the desktop app\'s layout, each with a reason', () {
      final unsupported = unsupportedActions(HostBackend.hc);
      expect(unsupported.map((entry) => entry.$1), [
        MultiplexerAction.focusPane,
        MultiplexerAction.splitPane,
        MultiplexerAction.zoomPane,
        MultiplexerAction.newTab,
        MultiplexerAction.newWorkspace,
        MultiplexerAction.prefixKeys,
      ]);
      for (final (_, reason) in unsupported) {
        expect(reason, isNotEmpty);
        expect(reason.split('\n'), hasLength(1));
      }
    });
  });

  group('ConnectTarget.hc', () {
    const target = ConnectTarget.hc('dev/t7', label: 'claude in api');

    test('attaches with hc and survives the session host id', () {
      expect(target.key, 'hc:dev/t7');
      expect(target.title, 'claude in api');
      expect(target.startupCommand, 'hc attach -- dev/t7');
      final host = target.apply(
        buildHost('h').copyWith(startTmuxOnConnect: true),
      );
      expect(host.id, 'h#hc:dev/t7');
      expect(host.startTmuxOnConnect, isFalse);
      expect(
        ConnectTarget.fromSessionHostId(host.id),
        const ConnectTarget.hc('dev/t7'),
      );
    });

    test('round-trips through JSON and rejects an empty address', () {
      expect(ConnectTarget.fromJson(target.toJson()), target);
      expect(ConnectTarget.fromJson({'kind': 'hc', 'name': ''}), isNull);
      expect(ConnectTarget.fromSessionHostId('h#hc:'), isNull);
    });
  });

  test('a terminal is named after its place in the app', () {
    const inSpace = HcTerminalInfo(
      address: 't1',
      agent: 'claude-code',
      cwd: '/root/Projects',
      where: 'Calendar / 1',
    );
    expect(inSpace.displayLabel, 'Calendar');
    const secondTab = HcTerminalInfo(
      address: 't2',
      agent: 'claude-code',
      where: 'Calendar / 2',
    );
    expect(secondTab.displayLabel, 'Calendar / 2');
    const named = HcTerminalInfo(address: 't3', name: 'api', where: 'X / 1');
    expect(named.displayLabel, 'api');
    const nowhere = HcTerminalInfo(
      address: 't4',
      agent: 'claude-code',
      cwd: '/root/Projects',
    );
    expect(nowhere.displayLabel, 'claude-code in Projects');
  });

  // CON-135: `terminal.list` over `hc connect` carries the title and the
  // app's space id, which `hc ls` leaves out.
  group('terminal.list (CON-135)', () {
    const answer =
        '{"id":1,"jsonrpc":"2.0","result":{"hidden_finished":0,'
        '"machines":[{"name":"omarchy","state":"connected"}],"terminals":['
        '{"address":"t1d","argv":["claude","--resume","x]"],'
        '"cwd":"/root/Projects/TheCalendar","foreground":{"name":"claude"},'
        '"labels":{"herdr.space":"sp1007","where":"Security Audit / 1"},'
        '"name":null,"state":"live",'
        '"status":{"app":"claude-code","state":"done"},'
        '"title":"Full first-pass review","turn":241},'
        '{"address":"omarchy/t1j","cwd":"/home/a","foreground":{"name":"bash"},'
        '"labels":{"herdr.space":"sp92ec","where":"1M plan / 2"},'
        '"state":"live","status":null,"title":"andreconde@omarchy:~",'
        '"turn":0}]}}';

    test('reads title, space id, where and the agent from the record', () {
      final terminals = HcListing.parseTerminals(answer);
      final first = terminals.first;
      expect(first.title, 'Full first-pass review');
      expect(first.spaceId, 'sp1007');
      expect(first.where, 'Security Audit / 1');
      expect(first.space, 'Security Audit');
      expect(first.agent, 'claude-code');
      expect(first.status, 'done');
      expect(first.turn, 241);
      expect(first.agentTitle, 'Full first-pass review');
      // A shell prompt title is no name: the space stands in.
      expect(terminals.last.agent, 'bash');
      expect(terminals.last.agentTitle, '1M plan / 2');
    });

    test('takes the answer line when hc connect prints more', () {
      final terminals = HcListing.parseTerminals(
        '{"jsonrpc":"2.0","method":"hello"}\n$answer\n',
      );
      expect(terminals.map((t) => t.address), ['t1d', 'omarchy/t1j']);
    });

    test('drops the spinner Claude Code puts before its title', () {
      const t = HcTerminalInfo(
        address: 't1',
        where: 'Calendar / 1',
        title: '✳ Calendar screenshots',
      );
      expect(t.agentTitle, 'Calendar screenshots');
      const braille = HcTerminalInfo(
        address: 't1',
        where: 'Calendar / 1',
        title: '⠂ Calendar screenshots',
      );
      expect(braille.agentTitle, 'Calendar screenshots');
      const none = HcTerminalInfo(address: 't1', where: 'Calendar / 1');
      expect(none.agentTitle, 'Calendar');
    });

    test('the list command asks terminal.list and falls back to hc ls', () {
      expect(HcCommands.list, contains('terminal.list'));
      expect(HcCommands.list, contains('hc connect'));
      expect(HcCommands.list, contains('hc ls --json'));
      expect(HcCommands.ls, contains('ls --json'));
      expect(HcCommands.ls, isNot(contains('terminal.list')));
    });
  });
}
