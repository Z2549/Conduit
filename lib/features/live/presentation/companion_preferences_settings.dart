import 'dart:async';

import 'package:conduit/core/l10n/legacy_tr.dart';
import 'package:conduit/core/presentation/theme_sheet.dart';
import 'package:conduit/features/live/presentation/companion_preferences.dart';
import 'package:flutter/material.dart';

/// Settings › Agents › Herdr and worktrees: Conductore in Herdr's sidebar,
/// and where later task starts put their worktrees.
class CompanionPreferencesCards extends StatefulWidget {
  const CompanionPreferencesCards({required this.preferences, super.key});

  final CompanionPreferences preferences;

  @override
  State<CompanionPreferencesCards> createState() =>
      _CompanionPreferencesCardsState();
}

class _CompanionPreferencesCardsState extends State<CompanionPreferencesCards> {
  late final TextEditingController _template = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.preferences.ensureLoaded().then((_) {
        if (!mounted) return;
        final current = widget.preferences.worktreeLocation;
        if (current.kind == WorktreeLocationKind.custom) {
          _template.text = current.template;
        }
      }),
    );
  }

  @override
  void dispose() {
    _template.dispose();
    super.dispose();
  }

  static String _label(WorktreeLocationKind kind) => switch (kind) {
    WorktreeLocationKind.nextToRepo => tr('Next to the repo'),
    WorktreeLocationKind.herdr => tr("Herdr's default"),
    WorktreeLocationKind.custom => tr('Custom'),
  };

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) {
        final worktree = preferences.worktreeLocation;
        final customValid = WorktreeLocation.validTemplate(_template.text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSwitchCard(
              switchKey: const ValueKey('herdr-sidebar-switch'),
              icon: Icons.view_sidebar_outlined,
              title: tr("Show Conductore in Herdr's sidebar"),
              subtitle: tr('Pending approvals and cost as Herdr sidebar '
                  'tokens (\$conductore_pending, \$conductore_cost, '
                  '\$conductore_today) while this device watches the '
                  'machine. Add them to a sidebar row in your Herdr config '
                  'to see them.'),
              value: preferences.herdrSidebar,
              onChanged: (on) => unawaited(preferences.setHerdrSidebar(on)),
            ),
            const SizedBox(height: 10),
            SettingsSwitchCard(
              switchKey: const ValueKey('tmux-live-switch'),
              icon: Icons.bolt_outlined,
              title: tr('Live tmux updates (adds a hidden tmux client)'),
              subtitle: tr('Off: the phone lists tmux itself. On: tmux '
                  'changes arrive at once, but tmux ls shows one more '
                  "attached client and that session's activity time and "
                  'attach hooks move.'),
              value: preferences.liveTmux,
              onChanged: (on) => unawaited(preferences.setLiveTmux(on)),
            ),
            const SizedBox(height: 10),
            SettingsSegmentCard<WorktreeLocationKind>(
              key: const ValueKey('worktree-location-setting'),
              icon: Icons.account_tree_outlined,
              title: tr('Worktree location for new tasks'),
              description: trf(
                tr('Where a task started from here gets its git worktree: '
                '{path}.'),
                {'path': worktree.describe()},
              ),
              values: WorktreeLocationKind.values,
              label: _label,
              selected: worktree.kind,
              onChanged: (kind) => unawaited(
                preferences.setWorktreeLocation(switch (kind) {
                  WorktreeLocationKind.nextToRepo =>
                    const WorktreeLocation.nextToRepo(),
                  WorktreeLocationKind.herdr => const WorktreeLocation.herdr(),
                  WorktreeLocationKind.custom => () {
                    if (!WorktreeLocation.validTemplate(_template.text)) {
                      _template.text = '~/worktrees/<repo>/<branch>';
                    }
                    return WorktreeLocation.custom(_template.text.trim());
                  }(),
                }),
              ),
            ),
            if (worktree.kind == WorktreeLocationKind.custom) ...[
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('worktree-template-field'),
                controller: _template,
                decoration: InputDecoration(
                  labelText: tr('Path template'),
                  helperText: tr('Use <repo> and <branch>'),
                  errorText: _template.text.isEmpty || customValid
                      ? null
                      : tr('It must contain <branch>'),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (value) {
                  if (WorktreeLocation.validTemplate(value.trim())) {
                    unawaited(
                      preferences.setWorktreeLocation(
                        WorktreeLocation.custom(value.trim()),
                      ),
                    );
                  }
                },
              ),
            ],
          ],
        );
      },
    );
  }
}
