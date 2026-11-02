import 'package:conduit/features/desktop_shell/domain/hc_documents.dart';
import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // docs/herdr-core-contract.md, sheprd-view v1.
  final viewJson = {
    'v': 1,
    'projects': [
      {
        'name': 'Conductore',
        'short': 'CO',
        'pinned': true,
        'collapsed': false,
        'members': ['local/Infra-Scripts'],
        'match': ['conductore'],
        'note': null,
      },
      {
        'name': 'Infrastructure',
        'short': 'IN',
        'members': ['dev/api'],
        'match': ['infra', 'conductore'],
      },
      {
        'name': '',
        'match': ['ignored'],
      },
      'not a project',
    ],
    'hidden': ['dev/w12'],
    'filter': 'needs-you',
    'active_only': true,
    'other_collapsed': true,
    'marks': {
      'unread': ['local/t1'],
      'kept': ['dev/t3'],
      'dismissed': ['local/t4@7'],
    },
  };

  HcTerminalInfo terminal(
    String address, {
    String cwd = '',
    String name = '',
    String status = '',
    int turn = 0,
  }) => HcTerminalInfo(
    address: address,
    cwd: cwd,
    name: name,
    status: status,
    turn: turn,
  );

  group('HcSheprdView', () {
    final view = HcSheprdView.fromJson(viewJson)!;

    test('reads projects, filter and marks', () {
      expect(view.projects.map((p) => p.name), [
        'Conductore',
        'Infrastructure',
      ]);
      expect(view.projects.first.short, 'CO');
      expect(view.projects.first.pinned, isTrue);
      expect(view.projects.first.note, isNull);
      expect(view.filter, HcViewFilter.needsYou);
      expect(view.activeOnly, isTrue);
      expect(view.otherCollapsed, isTrue);
      expect(view.hidden, {'dev/w12'});
      expect(view.unread, {'local/t1'});
      expect(view.kept, {'dev/t3'});
      expect(view.dismissed, {'local/t4@7'});
    });

    test('is absent when the document was never written or is not v1', () {
      expect(HcSheprdView.fromJson(null), isNull);
      expect(HcSheprdView.fromJson({'v': 2, 'projects': <Object>[]}), isNull);
      expect(HcSheprdView.fromJson('text'), isNull);
    });

    test('members win over match rules', () {
      // Matches Conductore's rule by its folder, but is a member of
      // Infrastructure.
      expect(
        view.projectOf(terminal('dev/t2', cwd: '/srv/conductore/api')),
        isNotNull,
      );
      expect(
        view.projectOf(terminal('dev/t2', cwd: '/srv/conductore/api'))!.name,
        'Infrastructure',
      );
      expect(
        view.projectOf(terminal('t5', cwd: '/root/Infra-Scripts'))!.name,
        'Conductore',
        reason: 'local/ is the hub',
      );
    });

    test('the first matching rule wins, case-insensitively', () {
      expect(
        view.projectOf(terminal('t6', cwd: '/root/Conductore-Mobile'))!.name,
        'Conductore',
      );
      expect(
        view.projectOf(terminal('t7', name: 'infra deploy'))!.name,
        'Infrastructure',
      );
    });

    test('the rest go to Other', () {
      expect(view.projectOf(terminal('t8', cwd: '/root/Barbusano')), isNull);
    });

    test('needs you: unread, or blocked/done unless dismissed at its turn', () {
      expect(view.needsYou(terminal('t1')), isTrue, reason: 'unread');
      expect(view.needsYou(terminal('t2', status: 'working')), isFalse);
      expect(view.needsYou(terminal('t3', status: 'blocked')), isTrue);
      expect(
        view.needsYou(terminal('t4', status: 'done', turn: 7)),
        isFalse,
        reason: 'dismissed at turn 7',
      );
      expect(
        view.needsYou(terminal('t4', status: 'done', turn: 8)),
        isTrue,
        reason: 'the dismissal lapsed when the turn moved on',
      );
    });

    test('mark keys carry the machine, local for the hub', () {
      expect(HcSheprdView.markKey(terminal('t7')), 'local/t7');
      expect(HcSheprdView.markKey(terminal('dev/t7')), 'dev/t7');
    });
  });

  group('HcCards.byTerminal', () {
    test('groups open cards by terminal, without dismissed or done ones', () {
      final cards = HcCards.byTerminal({
        'v': 1,
        'cards': {
          't7/SHE-12': {
            'id': 'SHE-12',
            'terminal': 't7',
            'title': 'Stripe checkout',
            'status': 'dev',
            'questions': [
              {
                'n': 1,
                'text': 'Which provider?',
                'options': ['Stripe', 'Multibanco'],
                'recommend': 1,
                'state': 'open',
              },
              {'n': 2, 'text': 'EUR only?', 'state': 'sent'},
            ],
            'done': false,
            'dismissed': false,
          },
          't7/SHE-13': {'id': 'SHE-13', 'terminal': 't7', 'done': true},
          't8/SHE-14': {'id': 'SHE-14', 'terminal': 't8', 'dismissed': true},
          'broken': {'terminal': 't9'},
        },
        'inbox': <String, Object>{},
      });
      expect(cards.keys, ['t7']);
      final card = cards['t7']!.single;
      expect(card.headline, 'SHE-12 Stripe checkout');
      expect(card.openQuestions, 1);
      expect(card.questions.first.options, ['Stripe', 'Multibanco']);
    });

    test('a question being sent still counts as open, never unknown', () {
      final card = HcCards.byTerminal({
        'v': 1,
        'cards': {
          't7/SHE-12': {
            'id': 'SHE-12',
            'terminal': 't7',
            'born': 1790229500000,
            'questions': [
              {'n': 1, 'text': 'Which provider?', 'state': 'open'},
              {
                'n': 2,
                'text': 'EUR only?',
                'state': 'sending',
                'answer': 'yes',
                'claim': 'c-41',
                'claimed_at': '2026-11-02T01:00:00Z',
              },
              {'n': 3, 'text': 'Retry?', 'state': 'staged', 'answer': 'no'},
              {'n': 4, 'text': 'Ship?', 'state': 'sent', 'answer': 'yes'},
              {'n': 5, 'text': 'Old?', 'state': 'dismissed'},
            ],
          },
        },
        'inbox': {
          't7': [
            {'line': 'SHE-12 Q4 → yes', 'born': 1790229500000, 'read': false},
          ],
        },
      })['t7']!.single;
      final sending = card.questions[1];
      expect(sending.state, 'sending');
      expect(sending.isSending, isTrue);
      expect(sending.isOpen, isTrue);
      expect(card.openQuestions, 3);
    });

    test('an absent document has no cards', () {
      expect(HcCards.byTerminal(null), isEmpty);
      expect(HcCards.byTerminal({'v': 1}), isEmpty);
    });
  });
}
