import 'dart:convert';

/// The companion lists an agent's slash commands (`commands <sessionId>`,
/// CON-125).
const commandsCapability = 'commands';

/// Where a slash command comes from.
enum SlashCommandSource { builtin, custom, skill }

/// One entry of the composer's "/" list.
class SlashCommand {
  const SlashCommand(
    this.name,
    this.description, {
    this.source = SlashCommandSource.builtin,
    this.argumentHint,
    this.menu = false,
    this.project = false,
  });

  /// Without the slash: `compact`, `frontend:component`.
  final String name;
  final String description;
  final SlashCommandSource source;

  /// What the command takes (`<env>`), from a custom command's front
  /// matter.
  final String? argumentHint;

  /// Opens a picker or screen in the terminal when given no arguments.
  final bool menu;

  /// From the session's project folder rather than the personal one.
  final bool project;

  /// What picking it puts in the composer.
  String get insertText => '/$name ';
}

/// The commands one agent takes, and the "/" filter over them.
class SlashCommandList {
  const SlashCommandList(this.commands);

  final List<SlashCommand> commands;

  static const empty = SlashCommandList([]);

  /// Claude Code's own commands, for companions without `commands`. Keep
  /// in step with host/lib/commands.js BUILTIN.
  static const claudeBuiltins = SlashCommandList([
    SlashCommand('add-dir', 'Add a working directory'),
    SlashCommand('agents', 'Manage subagents', menu: true),
    SlashCommand('clear', 'Start a new conversation (clears the history)'),
    SlashCommand(
      'compact',
      'Compact the conversation, with optional focus instructions',
    ),
    SlashCommand('config', 'Open settings', menu: true),
    SlashCommand('context', 'Show what fills the context window'),
    SlashCommand('cost', "Show the session's token cost"),
    SlashCommand('doctor', 'Check the Claude Code installation'),
    SlashCommand(
      'export',
      'Export the conversation to a file or the clipboard',
      menu: true,
    ),
    SlashCommand('help', 'Show help and the available commands'),
    SlashCommand('hooks', 'Manage hooks', menu: true),
    SlashCommand('init', 'Write a CLAUDE.md for this project'),
    SlashCommand('mcp', 'Manage MCP servers', menu: true),
    SlashCommand('memory', 'Edit CLAUDE.md memory files', menu: true),
    SlashCommand('model', 'Set the model (no argument: pick one)', menu: true),
    SlashCommand('permissions', 'View or change permission rules', menu: true),
    SlashCommand('plugin', 'Manage plugins', menu: true),
    SlashCommand('pr-comments', 'Show the comments of a pull request'),
    SlashCommand('release-notes', 'Show the release notes'),
    SlashCommand('resume', 'Resume an earlier conversation', menu: true),
    SlashCommand('review', 'Review a pull request'),
    SlashCommand('rewind', 'Rewind the conversation or code', menu: true),
    SlashCommand('security-review', 'Security review of the pending changes'),
    SlashCommand(
      'status',
      'Show version, model, account and connectivity',
      menu: true,
    ),
    SlashCommand('todos', 'List the current todo items'),
    SlashCommand('usage', 'Show plan usage limits', menu: true),
  ]);

  /// The companion's `commands` reply: `{builtin, custom, skills}`, each
  /// `[{name, description, scope?, argumentHint?, menu?}]`. Throws a
  /// [FormatException] when it is not that shape.
  static SlashCommandList parse(String stdout) {
    final decoded = jsonDecode(stdout.trim());
    if (decoded is! Map) {
      throw const FormatException('commands: not an object');
    }
    List<SlashCommand> read(String key, SlashCommandSource source) {
      final list = decoded[key];
      if (list is! List) return const [];
      return [
        for (final entry in list)
          if (entry is Map &&
              entry['name'] is String &&
              (entry['name'] as String).isNotEmpty)
            SlashCommand(
              entry['name'] as String,
              entry['description'] is String
                  ? entry['description'] as String
                  : '',
              source: source,
              argumentHint: entry['argumentHint'] is String
                  ? entry['argumentHint'] as String
                  : null,
              menu: entry['menu'] == true,
              project: entry['scope'] == 'project',
            ),
      ];
    }

    return SlashCommandList([
      ...read('custom', SlashCommandSource.custom),
      ...read('skills', SlashCommandSource.skill),
      ...read('builtin', SlashCommandSource.builtin),
    ]);
  }

  /// The "/" query in [text], or null when the list should not show: the
  /// text starts with `/` and the name is still being typed (no space or
  /// line break yet).
  static String? queryOf(String text) {
    if (!text.startsWith('/')) return null;
    final query = text.substring(1);
    if (query.contains(RegExp(r'\s'))) return null;
    return query;
  }

  /// The commands matching [query]: names starting with it first, then
  /// names or descriptions containing it; custom commands and skills
  /// before built-ins within each.
  List<SlashCommand> filter(String query) {
    final q = query.toLowerCase();
    if (q.isEmpty) return commands;
    final starts = <SlashCommand>[];
    final contains = <SlashCommand>[];
    for (final command in commands) {
      final name = command.name.toLowerCase();
      if (name.startsWith(q) || name.split(':').last.startsWith(q)) {
        starts.add(command);
      } else if (name.contains(q) ||
          command.description.toLowerCase().contains(q)) {
        contains.add(command);
      }
    }
    return [...starts, ...contains];
  }
}
