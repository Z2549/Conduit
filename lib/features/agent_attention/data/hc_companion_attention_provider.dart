import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/data/conductore_host_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/hc_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';

/// The companion on a Herdr app machine (CON-134): what it adds (Chat View,
/// approvals, messages) on the agents `hc ls` says are there, in the state
/// hc gives them. The companion alone calls every idle Claude "waiting for
/// your input" and still lists sessions that left long ago.
///
/// Only this machine's terminals: the machines hc reaches report through
/// their own monitor, and counting them here would count them twice.
class HcCompanionProvider extends ConductoreHostAttentionProvider {
  const HcCompanionProvider({this.keepHerdr = false, this.keepTmux = false});

  /// The machine also uses the Herdr TUI or tmux: the companion's agents
  /// there stay.
  final bool keepHerdr;
  final bool keepTmux;

  static const _timeout = Duration(seconds: 10);

  // hc has no change stream here: the state comes from polling `hc ls`.
  @override
  bool get supportsWatch => false;

  @override
  Future<AgentAttentionSnapshot> fetchAgents(AgentCommandRunner runner) async {
    final snapshot = await super.fetchAgents(runner);
    final result = await runner.run(HcCommands.ls, timeout: _timeout);
    return switch (HcListing.interpret(result)) {
      RemoteListingAvailable(:final items) => AgentAttentionSnapshot(
        agents: merge(
          snapshot.agents,
          items,
          keepHerdr: keepHerdr,
          keepTmux: keepTmux,
        ),
        sequence: snapshot.sequence,
        capabilities: snapshot.capabilities,
        kinds: snapshot.kinds,
      ),
      RemoteListingNotInstalled() => snapshot,
      RemoteListingNotRunning(:final message) ||
      RemoteListingFailed(
        :final message,
      ) => throw AppFailure('hc reported an error.', message),
    };
  }

  /// One agent per live local terminal that reports a status: the
  /// companion's session in it when there is one (named after its place in
  /// the app; a pending approval keeps it needing you), else hc's own.
  static List<AgentInfo> merge(
    List<AgentInfo> companion,
    List<HcTerminalInfo> terminals, {
    bool keepHerdr = false,
    bool keepTmux = false,
  }) {
    final local = terminals.where((terminal) => terminal.machine.isEmpty);
    final sessions = <String, AgentInfo>{
      for (final agent in companion)
        if (agent.herdrServer == HcAttentionProvider.serverId)
          agent.pane ?? '': agent,
    };
    return [
      for (final agent in HcAttentionProvider.agentsOf(local.toList()))
        switch (sessions[agent.id]) {
          final session? => session.copyWith(
            name: agent.name,
            state: session.pendingRequests.isNotEmpty
                ? session.state
                : agent.state,
          ),
          null => agent,
        },
      for (final agent in companion)
        if (agent.herdrServer != HcAttentionProvider.serverId &&
            (agent.workspace != null
                ? keepHerdr
                : keepTmux && agent.tab != null))
          agent,
    ];
  }
}
