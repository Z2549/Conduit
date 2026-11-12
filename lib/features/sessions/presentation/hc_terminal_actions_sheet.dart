import 'dart:async';

import 'package:conduit/core/l10n/legacy_tr.dart';
import 'package:conduit/core/presentation/adaptive_modal.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/desktop_shell/domain/hc_documents.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:flutter/material.dart';

/// What the phone can do with one hc terminal without opening it
/// (CON-100000): answer its agent's card questions (CON-129), read its
/// screen, send it a line, press a key. The desktop
/// app's own actions are listed disabled, each with why.
///
/// Commands run over [runner], the picker's exec channel.
Future<void> showHcTerminalActions({
  required BuildContext context,
  required AgentCommandRunner runner,
  required HcTerminalInfo terminal,
  required VoidCallback onOpen,
  List<HcCard> cards = const [],
}) {
  return showAdaptiveModal<void>(
    kind: AdaptiveModalKind.dialog,
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => HcTerminalActionsSheet(
      runner: runner,
      terminal: terminal,
      cards: cards,
      onOpen: () {
        Navigator.of(context).pop();
        onOpen();
      },
    ),
  );
}

class HcTerminalActionsSheet extends StatefulWidget {
  const HcTerminalActionsSheet({
    required this.runner,
    required this.terminal,
    required this.onOpen,
    this.cards = const [],
    super.key,
  });

  final AgentCommandRunner runner;
  final HcTerminalInfo terminal;
  final VoidCallback onOpen;

  /// The agent's open cards; their open questions can be answered here.
  final List<HcCard> cards;

  @override
  State<HcTerminalActionsSheet> createState() => _HcTerminalActionsSheetState();
}

class _HcTerminalActionsSheetState extends State<HcTerminalActionsSheet> {
  static const _timeout = Duration(seconds: 15);

  /// The last line about a command: what it did, or why it did not.
  String? _note;
  bool _busy = false;

  String get _address => widget.terminal.address;

  /// Questions answered from this sheet (`CON-1#2`), shown as sent.
  final _answered = <String, String>{};

  /// Runs [command]; null when it worked, else why not.
  Future<String?> _run(String command) async {
    try {
      final result = await widget.runner.run(command, timeout: _timeout);
      if (result.exitCode == null || result.exitCode == 0) return null;
      return HcListing.errorMessage(result.stderr.trim(), result.exitCode);
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> _act(String command, String done) async {
    setState(() => _busy = true);
    final problem = await _run(command);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = problem ?? done;
    });
  }

  Future<void> _read() async {
    setState(() => _busy = true);
    String text;
    try {
      final result = await widget.runner.run(
        HcCommands.read(_address),
        timeout: _timeout,
      );
      text = result.exitCode == null || result.exitCode == 0
          ? result.stdout
          : HcListing.errorMessage(result.stderr.trim(), result.exitCode);
    } catch (error) {
      text = error.toString();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.terminal.displayLabel),
        content: SingleChildScrollView(
          reverse: true,
          child: SelectableText(
            text.trimRight(),
            key: const ValueKey('hc-read-text'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send to ${widget.terminal.displayLabel}'),
        content: TextField(
          key: const ValueKey('hc-send-field'),
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          decoration: InputDecoration(
            helperText: tr('Pasted, then Enter once nobody is typing there.'),
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(tr('Send')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _act(HcCommands.send(_address, text), 'Sent.');
  }

  Future<void> _answer(HcCard card, HcCardQuestion q, String answer) async {
    setState(() => _busy = true);
    final problem = await _run(
      HcCommands.answerCard(_address, card.id, q.number, answer),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (problem == null) _answered['${card.id}#${q.number}'] = answer;
      _note = problem ?? 'Sent to ${card.id}: $answer';
    });
  }

  Future<void> _answerOther(HcCard card, HcCardQuestion q) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _AnswerDialog(card: card, question: q),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _answer(card, q, text.trim());
  }

  /// One open question: its text, an answer chip per option and Other….
  Widget _question(HcCard card, HcCardQuestion q) {
    final theme = Theme.of(context);
    final sent = _answered['${card.id}#${q.number}'];
    return Padding(
      key: ValueKey('hc-question-${card.id}-${q.number}'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${card.id} Q${q.number}: ${q.text}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          if (sent != null)
            Text('→ $sent (sent)', style: theme.textTheme.bodySmall)
          else if (q.isSending)
            Text(tr('Being sent…'), style: theme.textTheme.bodySmall)
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in q.options)
                  ActionChip(
                    key: ValueKey('hc-answer-${card.id}-${q.number}-$option'),
                    label: Text(option),
                    onPressed: _busy
                        ? null
                        : () => unawaited(_answer(card, q, option)),
                  ),
                ActionChip(
                  key: ValueKey('hc-answer-${card.id}-${q.number}-other'),
                  label: Text(tr('Other…')),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_answerOther(card, q)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              widget.terminal.displayLabel,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text(
              [
                _address,
                if (widget.terminal.cwd.isNotEmpty) widget.terminal.cwd,
              ].join(' · '),
            ),
          ),
          for (final card in widget.cards)
            for (final q in card.questions.where((q) => q.isOpen))
              _question(card, q),
          ListTile(
            key: const ValueKey('hc-action-open'),
            leading: const Icon(Icons.terminal_rounded),
            title: Text(tr('Open')),
            subtitle: const Text('Attach here; ctrl+\\ detaches.'),
            onTap: widget.onOpen,
          ),
          ListTile(
            key: const ValueKey('hc-action-read'),
            leading: const Icon(Icons.article_outlined),
            title: Text(tr('Read')),
            subtitle: Text(tr('Its screen and the last 200 lines.')),
            enabled: !_busy,
            onTap: () => unawaited(_read()),
          ),
          ListTile(
            key: const ValueKey('hc-action-send'),
            leading: const Icon(Icons.send_outlined),
            title: Text(tr('Send…')),
            subtitle: const Text(
              'A line and Enter. A program waiting on a decision is answered '
              'in the terminal itself.',
            ),
            enabled: !_busy,
            onTap: () => unawaited(_send()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (label, key) in const [
                  ('Enter', 'enter'),
                  ('Esc', 'esc'),
                  ('Ctrl+C', 'ctrl+c'),
                ])
                  ActionChip(
                    key: ValueKey('hc-key-$key'),
                    label: Text(label),
                    onPressed: _busy
                        ? null
                        : () => unawaited(
                            _act(
                              HcCommands.keys(_address, [key]),
                              'Pressed $label.',
                            ),
                          ),
                  ),
              ],
            ),
          ),
          if (_note case final note?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                note,
                key: const ValueKey('hc-action-note'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          const Divider(),
          for (final (action, reason) in unsupportedActions(HostBackend.hc))
            ListTile(
              key: ValueKey('hc-unsupported-${action.name}'),
              enabled: false,
              dense: true,
              leading: const Icon(Icons.block_outlined),
              title: Text(action.label),
              subtitle: Text(reason),
            ),
        ],
      ),
    );
  }
}

/// A written answer to one card question. It owns its controller, so the
/// field outlives the dialog's closing animation.
class _AnswerDialog extends StatefulWidget {
  const _AnswerDialog({required this.card, required this.question});

  final HcCard card;
  final HcCardQuestion question;

  @override
  State<_AnswerDialog> createState() => _AnswerDialogState();
}

class _AnswerDialogState extends State<_AnswerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.card.id} Q${widget.question.number}'),
    content: TextField(
      key: const ValueKey('hc-answer-field'),
      controller: _controller,
      autofocus: true,
      minLines: 1,
      maxLines: 4,
      decoration: InputDecoration(
        helperText: widget.question.text,
        helperMaxLines: 4,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: Text(tr('Send')),
      ),
    ],
  );
}
