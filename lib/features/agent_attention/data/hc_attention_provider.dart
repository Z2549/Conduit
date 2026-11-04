import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';

/// Reads agent state from herdr-core's `hc ls --json` (CON-100000), for
/// machines whose backend is the Herdr app.
///
/// Only terminals whose program reports a status (OSC 7501: coding agents
/// do, plain shells and `cat` do not) count as agents; hc's words map onto
/// the app's states as Herdr's do. There is no focus command: hc cannot
/// move the desktop app's focus, so the phone opens the terminal instead.
class HcAttentionProvider extends AgentAttentionProvider {
  const HcAttentionProvider();

  static const _commandTimeout = Duration(seconds: 10);

  /// The [AgentInfo.herdrServer] of every agent hc lists: their id is an hc
  /// terminal address, opened with `hc attach` rather than a Herdr
  /// workspace or tmux pane.
  static const serverId = 'hc';

  @override
  String get id => 'hc';

  @override
  String get label => 'Herdr app';

  @override
  Future<AgentAttentionSnapshot> fetchAgents(AgentCommandRunner runner) async {
    final result = await runner.run(HcCommands.list, timeout: _commandTimeout);
    return switch (HcListing.interpret(result)) {
      RemoteListingAvailable(:final items) => AgentAttentionSnapshot(
        agents: agentsOf(items),
      ),
      RemoteListingNotInstalled() => throw const AgentProviderUnavailable(
        'hc (herdr-core) is not installed on this machine.',
      ),
      RemoteListingNotRunning(:final message) ||
      RemoteListingFailed(
        :final message,
      ) => throw AppFailure('hc reported an error.', message),
    };
  }

  @override
  String? focusCommand(AgentInfo agent) => null;

  /// The agents among [terminals]: live ones that reported a status.
  static List<AgentInfo> agentsOf(List<HcTerminalInfo> terminals) => [
    for (final terminal in terminals)
      if (terminal.live && terminal.status.isNotEmpty)
        AgentInfo(
          id: terminal.address,
          name: terminal.displayLabel,
          kind: terminal.agent,
          state: stateOf(terminal.status),
          stateSequence: terminal.turn,
          pane: terminal.address,
          herdrServer: serverId,
        ),
  ];

  static AgentAttentionState stateOf(String status) => switch (status) {
    'working' => AgentAttentionState.working,
    // A permission, question or sign-in: a person is needed.
    'blocked' => AgentAttentionState.needsInput,
    'done' => AgentAttentionState.finished,
    'idle' => AgentAttentionState.idle,
    'error' => AgentAttentionState.blocked,
    _ => AgentAttentionState.unknown,
  };
}
