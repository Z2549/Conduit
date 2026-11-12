import 'package:conduit/core/l10n/legacy_tr.dart';
import 'package:conduit/core/presentation/conduit_brand.dart';
import 'package:flutter/material.dart';

class EmptyTerminalState extends StatelessWidget {
  const EmptyTerminalState({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ConduitGlyph(size: 48),
            const SizedBox(height: 16),
            Text(tr('No sessions open'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(tr('Pick a machine to spin up a new tab.'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text(tr('Back to machines')),
            ),
          ],
        ),
      ),
    );
  }
}
