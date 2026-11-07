// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:conduit/core/app_failure.dart';
import 'package:conduit/core/connection_problem.dart';
import 'package:conduit/features/agent_attention/data/hc_attention_provider.dart';
import 'package:conduit/features/agent_attention/data/herdr_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention.dart';
import 'package:conduit/features/agent_attention/domain/agent_attention_provider.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/agent_attention/presentation/agent_attention_controller.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/live/domain/live_host_model.dart';
import 'package:conduit/features/live/presentation/live_host_hub.dart';
import 'package:conduit/features/sessions/domain/connect_target.dart';
import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';
import 'package:flutter/foundation.dart';

/// Where the home board is for the selected machine.
enum HomeBoardPhase {
  /// No machine selected, or a machine the board does not list (local).
  idle,

  /// Listing waits for an explicit request: the login uses a hardware key
  /// (each connection asks for a touch) or the machine was never connected
  /// (its host key would have to be trusted first). See
  /// [HomeBoardController.requestReason].
  awaitingRequest,

  /// First fetch in flight; nothing to show yet.
  loading,

  /// Workspaces (and their agent panes) are listed.
  ready,

  /// Herdr is not installed on the machine; polling has stopped.
  notInstalled,

  /// Herdr is installed but its server is not running.
  notRunning,

  /// The last fetch failed; [HomeBoardState.workspaces] may hold stale data.
  failed,
}

/// Why the board waits for an explicit request before listing.
enum HomeBoardRequestReason {
  /// Each new connection asks for a hardware-key touch.
  hardwareKey,

  /// The machine was never connected, so its host key is not trusted yet.
  neverConnected,
}

/// One Herdr pane that runs an agent, with its tab resolved to a label.
@immutable
class HomeBoardPane {
  const HomeBoardPane({required this.agent, this.tabLabel = ''});

  final AgentInfo agent;

  /// Label of the pane's Herdr tab; empty when unknown.
  final String tabLabel;

  /// Human title of the pane: the agent's live name or terminal title.
  String get title => agent.name;
}

/// One Herdr workspace with the agent panes inside it.
@immutable
class HomeBoardWorkspace {
  const HomeBoardWorkspace({required this.workspace, this.panes = const []});

  final HerdrWorkspaceInfo workspace;
  final List<HomeBoardPane> panes;

  String get id => workspace.id;
  String get label => workspace.label;

  /// Most urgent agent state in the workspace (panes first, then Herdr's
  /// own workspace-level status).
  AgentAttentionState? get summary {
    AgentAttentionState? best;
    for (final pane in panes) {
      final state = pane.agent.state;
      if (best == null || homeBoardPriority(state) < homeBoardPriority(best)) {
        best = state;
      }
    }
    return best ?? herdrStatusToState(workspace.agentStatus);
  }
}

/// Whether tmux could be listed on the machine.
enum HomeTmuxStatus {
  /// Not listed yet (or the connection failed before tmux answered).
  unknown,

  /// `tmux list-sessions` answered; [HomeBoardState.tmuxSessions] holds
  /// the sessions (empty when no server runs).
  available,

  /// tmux is not installed on the machine.
  notInstalled,

  /// tmux answered with an error.
  failed,
}

/// One tmux window, from `tmux list-windows`.
@immutable
class TmuxWindowInfo {
  const TmuxWindowInfo({
    required this.index,
    required this.name,
    this.panes = 1,
    this.active = false,
    this.activity,
  });

  final int index;
  final String name;
  final int panes;
  final bool active;

  /// tmux's `window_activity`: when the window last had output.
  final DateTime? activity;

  @override
  bool operator ==(Object other) =>
      other is TmuxWindowInfo &&
      other.index == index &&
      other.name == name &&
      other.panes == panes &&
      other.active == active &&
      other.activity == activity;

  @override
  int get hashCode => Object.hash(index, name, panes, active, activity);
}

/// tmux commands the home page runs besides the session listing.
abstract final class HomeTmuxCommands {
  /// Exact-match target for [session] (`=name`), so a session called
  /// `web` never resolves to `web-old`.
  static String _target(String session, [String window = '']) =>
      ConnectTarget.shellQuote(
        window.isEmpty ? '=$session' : '=$session:$window',
      );

  /// One tab-separated line per window: index, name, pane count, active,
  /// last activity (epoch seconds).
  static String listWindows(String session) =>
      'tmux list-windows -t ${_target(session)} -F '
      '"\$(printf \'#{window_index}\\t#{window_name}\\t#{window_panes}'
      '\\t#{window_active}\\t#{window_activity}\')"';

  /// Makes [index] the session's current window, so the next attach
  /// shows it.
  static String selectWindow(String session, int index) =>
      'tmux select-window -t ${_target(session, '$index')}';

  /// Parses [listWindows] output; lines that do not fit are skipped.
  static List<TmuxWindowInfo> parseWindows(String raw) {
    final windows = <TmuxWindowInfo>[];
    for (final line in raw.split('\n')) {
      final fields = line.split('\t');
      if (fields.length < 2) continue;
      final index = int.tryParse(fields[0].trim());
      if (index == null) continue;
      windows.add(
        TmuxWindowInfo(
          index: index,
          name: fields[1].trim(),
          panes: fields.length > 2 ? int.tryParse(fields[2].trim()) ?? 1 : 1,
          active: fields.length > 3 && fields[3].trim() == '1',
          activity: switch (fields.length > 4
              ? int.tryParse(fields[4].trim())
              : null) {
            final seconds? => DateTime.fromMillisecondsSinceEpoch(
              seconds * 1000,
              isUtc: true,
            ),
            null => null,
          },
        ),
      );
    }
    return windows;
  }
}

/// Snapshot rendered by the home board.
@immutable
class HomeBoardState {
  const HomeBoardState({
    this.phase = HomeBoardPhase.idle,
    this.workspaces = const [],
    this.tmux = HomeTmuxStatus.unknown,
    this.tmuxSessions = const [],
    this.message,
    this.problem,
    this.updatedAt,
    this.refreshing = false,
    this.backend = HostBackend.herdr,
    this.hcTerminals = const [],
  });

  /// Where listing stands: the connection, and Herdr's availability once
  /// the machine answered ([HomeBoardPhase.notInstalled] and
  /// [HomeBoardPhase.notRunning] speak about Herdr only; tmux has
  /// [tmux]).
  final HomeBoardPhase phase;
  final List<HomeBoardWorkspace> workspaces;

  /// Whether tmux answered, and its sessions.
  final HomeTmuxStatus tmux;
  final List<TmuxSessionInfo> tmuxSessions;

  /// Error or availability text for [HomeBoardPhase.failed],
  /// [HomeBoardPhase.notInstalled] and [HomeBoardPhase.notRunning].
  final String? message;

  /// For [HomeBoardPhase.failed]: what went wrong connecting (the machine
  /// is unreachable, sign-in failed), or null when the machine answered
  /// and a command failed ([message] says how).
  final ConnectionProblem? problem;
  final DateTime? updatedAt;

  /// A fetch is running while older data is on screen.
  final bool refreshing;

  /// The machine's backend. On [HostBackend.hc] the board never runs the
  /// herdr CLI: [hcTerminals] holds `hc ls`, [workspaces] are the Herdr
  /// app's spaces made from it (CON-130, see [hcWorkspaces]), and [phase]
  /// speaks about hc instead of Herdr.
  final HostBackend backend;

  /// The machine's hc terminals (only on [HostBackend.hc]).
  final List<HcTerminalInfo> hcTerminals;

  bool get onHc => backend == HostBackend.hc;

  int get paneCount =>
      workspaces.fold(0, (count, workspace) => count + workspace.panes.length);

  int get attentionCount => workspaces.fold(
    0,
    (count, workspace) =>
        count +
        workspace.panes.where((pane) => pane.agent.state.needsAttention).length,
  );

  /// Whether tmux sessions can be listed here (tmux answered).
  bool get hasTmux => tmux == HomeTmuxStatus.available;

  /// Whether [other] shows the same board: everything but [updatedAt] and
  /// [refreshing], which nothing draws. A poll that lists what is already
  /// on screen changes nothing for listeners.
  bool sameBoardAs(HomeBoardState other) {
    if (other.phase != phase ||
        other.backend != backend ||
        !listEquals(other.hcTerminals, hcTerminals) ||
        other.tmux != tmux ||
        other.message != message ||
        !listEquals(other.tmuxSessions, tmuxSessions) ||
        other.workspaces.length != workspaces.length ||
        !_sameProblem(other.problem, problem)) {
      return false;
    }
    for (var i = 0; i < workspaces.length; i++) {
      final a = workspaces[i];
      final b = other.workspaces[i];
      if (a.workspace != b.workspace ||
          !listEquals(a.workspace.tabs, b.workspace.tabs) ||
          a.panes.length != b.panes.length) {
        return false;
      }
      for (var p = 0; p < a.panes.length; p++) {
        if (a.panes[p].agent != b.panes[p].agent ||
            a.panes[p].tabLabel != b.panes[p].tabLabel) {
          return false;
        }
      }
    }
    return true;
  }

  static bool _sameProblem(ConnectionProblem? a, ConnectionProblem? b) =>
      identical(a, b) ||
      (a != null &&
          b != null &&
          a.kind == b.kind &&
          a.title == b.title &&
          a.message == b.message &&
          a.detail == b.detail);

  HomeBoardState copyWith({
    HomeBoardPhase? phase,
    List<HomeBoardWorkspace>? workspaces,
    HomeTmuxStatus? tmux,
    List<TmuxSessionInfo>? tmuxSessions,
    String? message,
    ConnectionProblem? problem,
    bool clearMessage = false,
    DateTime? updatedAt,
    bool? refreshing,
    HostBackend? backend,
    List<HcTerminalInfo>? hcTerminals,
  }) {
    return HomeBoardState(
      phase: phase ?? this.phase,
      workspaces: workspaces ?? this.workspaces,
      tmux: tmux ?? this.tmux,
      tmuxSessions: tmuxSessions ?? this.tmuxSessions,
      message: clearMessage ? null : message ?? this.message,
      problem: clearMessage ? null : problem ?? this.problem,
      updatedAt: updatedAt ?? this.updatedAt,
      refreshing: refreshing ?? this.refreshing,
      backend: backend ?? this.backend,
      hcTerminals: hcTerminals ?? this.hcTerminals,
    );
  }
}

/// Sort key for agent states: lower is more urgent.
int homeBoardPriority(AgentAttentionState state) => switch (state) {
  AgentAttentionState.needsInput => 0,
  AgentAttentionState.blocked => 1,
  AgentAttentionState.working => 2,
  AgentAttentionState.finished => 3,
  AgentAttentionState.idle => 4,
  AgentAttentionState.unknown => 5,
};

/// Maps Herdr's raw `agent_status` (`idle`, `working`, `blocked`, `done`,
/// `unknown`) to a state; null when there is nothing to report.
AgentAttentionState? herdrStatusToState(String raw) {
  return switch (raw.toLowerCase()) {
    'working' || 'running' || 'busy' => AgentAttentionState.working,
    'blocked' || 'waiting' || 'needs_input' => AgentAttentionState.needsInput,
    'done' || 'finished' => AgentAttentionState.finished,
    'idle' || 'ready' => AgentAttentionState.idle,
    _ => null,
  };
}

/// Live board of one machine's tmux sessions, Herdr workspaces and agent
/// panes for the home page.
///
/// It polls over its own on-demand exec channel (so it works before any
/// terminal session exists), only while [setVisible] says the home page is
/// on screen, one fetch at a time, backing off after failures. The channel
/// is closed whenever the board is hidden or switches machine. Hardware-key
/// machines are listed only after [requestLoad]: every new connection asks
/// for a key touch.
///
/// With a [liveFeed] whose companion pushes Herdr and tmux
/// (`docs/herdr-live.md`), the board polls nothing: it draws the pushed
/// model, and polls only when that machine's companion cannot push.
class HomeBoardController extends ChangeNotifier {
  HomeBoardController({
    required AgentCommandRunnerFactory runnerFactory,
    AgentAttentionProvider provider = const HerdrAttentionProvider(),
    Duration pollInterval = const Duration(seconds: 5),
    LiveHostFeed? Function(SavedHost host)? liveFeed,
  }) : _runnerFactory = runnerFactory,
       _provider = provider,
       _pollInterval = pollInterval,
       _liveFeed = liveFeed;

  final AgentCommandRunnerFactory _runnerFactory;
  final AgentAttentionProvider _provider;
  final Duration _pollInterval;
  final LiveHostFeed? Function(SavedHost host)? _liveFeed;

  /// The pushed feed this board reads while it is on screen, and its
  /// release.
  LiveHostFeed? _feed;
  VoidCallback? _releaseFeed;

  /// Whether the board draws the pushed model instead of polling.
  bool get live => _feed?.support == LiveSupport.supported;

  /// tmux as this board lists it itself while the companion pushes Herdr
  /// but not tmux (`tmux-live` off, the default): the usual listing, with
  /// the quiet backoff, at the board's own pace.
  Timer? _tmuxTimer;
  int _tmuxSkip = 0;
  int _tmuxQuiet = 0;
  bool _tmuxFetching = false;
  (HomeTmuxStatus, List<TmuxSessionInfo>)? _polledTmux;

  static const _timeout = Duration(seconds: 10);
  static const _maxBackoffTicks = 4;

  /// Consecutive failures after which polling stops until [refresh]: a
  /// rejected host key or a machine that is down should not keep asking.
  static const _maxFailures = 3;

  SavedHost? _host;
  AgentCommandRunner? _runner;
  Timer? _timer;
  bool _visible = false;
  bool _requested = false;

  /// The machine was reached before even though its saved record has no
  /// last-connected time (a trusted host key, an open session): it lists
  /// on its own.
  bool _connectedBefore = false;

  /// Generation of the fetch in flight, or null when idle.
  int? _fetchingGeneration;
  bool _disposed = false;
  int _generation = 0;
  int _failures = 0;
  int _skipTicks = 0;

  /// Polls in a row that found the board as it was. The longer a machine
  /// stays quiet, the more ticks are skipped: 5 s, then 10, 15 and at most
  /// 20 s between listings (a change, a refresh or coming back to the
  /// page returns to 5 s).
  int _quietPolls = 0;
  static const _quietPollsPerStep = 3;
  static const _maxQuietSkip = 3;
  HomeBoardState _state = const HomeBoardState();

  SavedHost? get host => _host;
  HomeBoardState get state => _state;
  bool get visible => _visible;

  /// Whether the board waits for [requestLoad] before listing.
  bool get _needsRequest => requestReason != null;

  /// Why listing waits for [requestLoad], or null when it polls on its own.
  HomeBoardRequestReason? get requestReason {
    final host = _host;
    if (host == null || _requested) return null;
    if (host.authMethod == SshAuthMethod.hardwareKey) {
      return HomeBoardRequestReason.hardwareKey;
    }
    if (host.lastConnectedAt == null && !_connectedBefore) {
      return HomeBoardRequestReason.neverConnected;
    }
    return null;
  }

  bool get _listable => _host != null && !_host!.isLocal;

  /// The machine runs the Herdr app (hc), not the herdr CLI.
  bool get _onHc => _host?.backend == HostBackend.hc;

  /// Machines (lower case) whose terminals this board leaves out of its
  /// spaces: `hc ls` on one machine lists the machines it reaches too, and
  /// those on the home page have their own board.
  Set<String> skipHcMachines = const {};

  /// Shows [host] on the board. Selecting the same machine again only
  /// refreshes its saved details; a different one starts over.
  ///
  /// [connectedBefore] marks a machine the app has reached before (its host
  /// key is trusted, or a session is open) so it lists without a request
  /// even when its saved record lost the last-connected time.
  void selectHost(SavedHost? host, {bool connectedBefore = false}) {
    if (_disposed) return;
    if (host?.id == _host?.id && _sameEndpoint(host, _host)) {
      final wasWaiting = _needsRequest;
      _host = host;
      _connectedBefore = _connectedBefore || connectedBefore;
      // A first connection trusts the host key; the board can start.
      if (wasWaiting && !_needsRequest) {
        _state = HomeBoardState(phase: _initialPhase());
        notifyListeners();
        _start();
      }
      return;
    }
    _generation += 1;
    _stopTimer();
    _detachFeed();
    unawaited(_closeRunner());
    _host = host;
    _requested = false;
    _connectedBefore = connectedBefore;
    _failures = 0;
    _skipTicks = 0;
    _quietPolls = 0;
    _state = HomeBoardState(phase: _initialPhase());
    notifyListeners();
    _start();
  }

  /// Whether [a] and [b] reach the machine the same way: an imported or
  /// synced record that changes the address or login starts over with a
  /// new channel instead of polling through the old one.
  static bool _sameEndpoint(SavedHost? a, SavedHost? b) =>
      a == null ||
      b == null ||
      (a.host == b.host &&
          a.port == b.port &&
          a.username == b.username &&
          a.authMethod == b.authMethod &&
          a.password == b.password &&
          a.privateKey == b.privateKey &&
          a.passphrase == b.passphrase);

  /// Starts polling while the home page is on screen and the app is in
  /// the foreground; stops it (and closes the channel) otherwise.
  void setVisible(bool visible) {
    if (_disposed || visible == _visible) return;
    _visible = visible;
    if (visible) {
      _quietPolls = 0;
      _skipTicks = 0;
      _start();
    } else {
      _stopTimer();
      _detachFeed();
      _generation += 1;
      unawaited(_closeRunner());
      if (_state.refreshing || _state.phase == HomeBoardPhase.loading) {
        _state = _state.copyWith(
          refreshing: false,
          phase: _state.phase == HomeBoardPhase.loading
              ? _initialPhase()
              : null,
        );
        notifyListeners();
      }
    }
  }

  /// Lists a hardware-key machine (one key touch), then keeps polling it.
  void requestLoad() {
    if (_disposed || !_listable) return;
    _requested = true;
    _failures = 0;
    _skipTicks = 0;
    _quietPolls = 0;
    _start(force: true);
  }

  /// Fetches now, skipping any failure backoff. A no-op for hardware-key
  /// machines that have not been requested yet.
  Future<void> refresh() async {
    if (_disposed || !_listable || _needsRequest) return;
    // Pushed: what is on screen is current.
    if (live) return;
    _failures = 0;
    _skipTicks = 0;
    _quietPolls = 0;
    if (_timer == null && _visible) {
      _startTimer();
    }
    await _fetch();
  }

  /// Focuses [agent]'s pane in Herdr (`herdr agent focus <pane>`).
  /// Nothing on an hc machine: hc cannot move the desktop app's focus.
  Future<void> focusPane(AgentInfo agent) async {
    if (_onHc) return;
    final command = _provider.focusCommand(agent);
    if (command == null) return;
    await _runBestEffort(command);
  }

  /// Focuses a whole workspace in Herdr.
  Future<void> focusWorkspace(String workspaceId) async {
    if (workspaceId.isEmpty || _onHc) return;
    await _runBestEffort(
      HerdrAttentionProvider.remoteCommand(
        'workspace focus ${ConnectTarget.shellQuote(workspaceId)}',
      ),
    );
  }

  Future<void> _runBestEffort(String command) async {
    final host = _host;
    if (_disposed || host == null || host.isLocal) return;
    try {
      final runner = _runner ??= _runnerFactory(host);
      await runner.run(command, timeout: _timeout);
    } catch (_) {
      // Focus is a nicety: the pane may be gone since the last poll.
    }
    if (!_visible && !_disposed) {
      // Sent from behind the terminal page: do not keep the channel open.
      await _closeRunner();
    }
  }

  /// Neither tmux nor Herdr is installed: polling stops until [refresh].
  bool get _nothingToPoll =>
      _state.phase == HomeBoardPhase.notInstalled &&
      _state.tmux == HomeTmuxStatus.notInstalled;

  /// Lists the windows of tmux [session] (for opening it at one).
  Future<List<TmuxWindowInfo>> listTmuxWindows(String session) async {
    final host = _host;
    if (_disposed || host == null || host.isLocal) return const [];
    try {
      final runner = _runner ??= _runnerFactory(host);
      final result = await runner.run(
        HomeTmuxCommands.listWindows(session),
        timeout: _timeout,
      );
      if (result.exitCode != null && result.exitCode != 0) return const [];
      return HomeTmuxCommands.parseWindows(result.stdout);
    } catch (_) {
      return const [];
    } finally {
      if (!_visible && !_disposed) await _closeRunner();
    }
  }

  /// Makes window [index] current in tmux [session] before attaching.
  Future<void> selectTmuxWindow(String session, int index) =>
      _runBestEffort(HomeTmuxCommands.selectWindow(session, index));

  HomeBoardPhase _initialPhase() {
    if (!_listable) return HomeBoardPhase.idle;
    if (_needsRequest) return HomeBoardPhase.awaitingRequest;
    return HomeBoardPhase.loading;
  }

  void _start({bool force = false}) {
    if (!_visible || !_listable || _needsRequest) return;
    if (_attachFeed()) return;
    if (!force && _nothingToPoll) return;
    if (_state.phase == HomeBoardPhase.awaitingRequest ||
        _state.phase == HomeBoardPhase.idle) {
      _state = _state.copyWith(phase: HomeBoardPhase.loading);
      notifyListeners();
    }
    _startTimer();
    unawaited(_fetch());
  }

  /// Reads the machine's pushed feed when its companion may push; false
  /// when the board polls instead.
  bool _attachFeed() {
    final host = _host;
    // The pushed model is Herdr's: an hc machine is polled with `hc ls`.
    // So is one that leaves out Herdr or tmux, which the model holds.
    if (host == null ||
        host.backend == HostBackend.hc ||
        !host.tools.containsAll(const {HostTool.herdr, HostTool.tmux})) {
      return false;
    }
    final feed = _feed ?? _liveFeed?.call(host);
    if (feed == null || feed.support == LiveSupport.unsupported) {
      return false;
    }
    if (_feed == null) {
      _feed = feed;
      feed.addListener(_onFeed);
      _releaseFeed = feed.acquire();
    }
    _stopTimer();
    if (_state.phase == HomeBoardPhase.awaitingRequest ||
        _state.phase == HomeBoardPhase.idle) {
      _state = _state.copyWith(phase: HomeBoardPhase.loading);
      notifyListeners();
    }
    _onFeed();
    return true;
  }

  void _detachFeed() {
    _stopTmuxPoll();
    _feed?.removeListener(_onFeed);
    _releaseFeed?.call();
    _feed = null;
    _releaseFeed = null;
  }

  void _onFeed() {
    final feed = _feed;
    if (_disposed || feed == null) return;
    switch (feed.support) {
      case LiveSupport.unknown:
        return;
      case LiveSupport.unsupported:
        // An older companion, or none: poll as before.
        _detachFeed();
        _start();
      case LiveSupport.supported:
        final tmuxPushed =
            feed.model.serverState(LiveHostModel.tmuxServerId) !=
            LiveServerState.off;
        if (tmuxPushed) {
          _stopTmuxPoll();
        } else {
          _startTmuxPoll();
        }
        _publishLive();
    }
  }

  void _publishLive() {
    final feed = _feed;
    if (_disposed || feed == null) return;
    final next = stateFromLive(feed.model, tmux: _polledTmux);
    if (next.sameBoardAs(_state)) return;
    _state = next;
    _failures = 0;
    notifyListeners();
  }

  void _startTmuxPoll() {
    if (_tmuxTimer != null) return;
    _tmuxQuiet = 0;
    _tmuxSkip = 0;
    _tmuxTimer = Timer.periodic(_pollInterval, (_) {
      if (_tmuxSkip > 0) {
        _tmuxSkip -= 1;
        return;
      }
      unawaited(_pollTmux());
    });
    unawaited(_pollTmux());
  }

  void _stopTmuxPoll() {
    _tmuxTimer?.cancel();
    _tmuxTimer = null;
    _polledTmux = null;
  }

  Future<void> _pollTmux() async {
    final host = _host;
    if (_disposed || _tmuxFetching || host == null || !_visible) return;
    _tmuxFetching = true;
    try {
      final runner = _runner ??= _runnerFactory(host);
      final result = await runner.run(
        RemoteSessionListing.tmuxListCommand,
        timeout: _timeout,
      );
      if (_disposed || _tmuxTimer == null) return;
      final polled = _interpretTmux(result);
      final previous = _polledTmux;
      final same =
          previous != null &&
          previous.$1 == polled.$1 &&
          listEquals(previous.$2, polled.$2);
      _tmuxQuiet = same ? _tmuxQuiet + 1 : 0;
      _tmuxSkip = (_tmuxQuiet ~/ _quietPollsPerStep).clamp(0, _maxQuietSkip);
      _polledTmux = polled;
      _publishLive();
    } catch (_) {
      // The next ticks try again; Herdr stays pushed meanwhile.
      _tmuxSkip = _maxBackoffTicks;
      unawaited(_closeRunner());
    } finally {
      _tmuxFetching = false;
    }
  }

  static (HomeTmuxStatus, List<TmuxSessionInfo>) _interpretTmux(
    AgentCommandResult result,
  ) => switch (RemoteSessionListing.interpretTmux(result)) {
    RemoteListingAvailable<TmuxSessionInfo>(:final items) => (
      HomeTmuxStatus.available,
      items,
    ),
    RemoteListingNotInstalled<TmuxSessionInfo>() => (
      HomeTmuxStatus.notInstalled,
      const <TmuxSessionInfo>[],
    ),
    RemoteListingNotRunning<TmuxSessionInfo>() => (
      HomeTmuxStatus.available,
      const <TmuxSessionInfo>[],
    ),
    RemoteListingFailed<TmuxSessionInfo>() => (
      HomeTmuxStatus.failed,
      const <TmuxSessionInfo>[],
    ),
  };

  /// The board the pushed [model] shows: the default Herdr server's
  /// workspaces, tabs and agents, and the tmux sessions ([tmux]: what the
  /// board listed itself while tmux is not pushed).
  @visibleForTesting
  static HomeBoardState stateFromLive(
    LiveHostModel model, {
    (HomeTmuxStatus, List<TmuxSessionInfo>)? tmux,
  }) {
    final herdr = LiveHostModel.herdrServerId('');
    final tmuxServer = model.entities['srv:${LiveHostModel.tmuxServerId}'];
    final tmuxError = tmuxServer?['error'];
    final (tmuxStatus, tmuxSessions) =
        tmux ??
        switch (model.serverState(LiveHostModel.tmuxServerId)) {
          LiveServerState.up => (
            HomeTmuxStatus.available,
            model.tmuxSessions(),
          ),
          LiveServerState.none
              when tmuxError is String && tmuxError.contains('not installed') =>
            (HomeTmuxStatus.notInstalled, const <TmuxSessionInfo>[]),
          LiveServerState.none => (
            HomeTmuxStatus.available,
            const <TmuxSessionInfo>[],
          ),
          LiveServerState.down => (
            HomeTmuxStatus.failed,
            const <TmuxSessionInfo>[],
          ),
          // Not pushed (tmux-live off): the board lists it itself.
          LiveServerState.unknown || LiveServerState.off => (
            HomeTmuxStatus.unknown,
            const <TmuxSessionInfo>[],
          ),
        };
    final herdrError = model.entities['srv:$herdr']?['error'];
    final now = DateTime.now();
    switch (model.serverState(herdr)) {
      case LiveServerState.up:
        return HomeBoardState(
          phase: HomeBoardPhase.ready,
          workspaces: buildBoard(
            model.workspaces(),
            model.herdrTabs(),
            model.herdrAgents(),
          ),
          tmux: tmuxStatus,
          tmuxSessions: tmuxSessions,
          updatedAt: now,
        );
      case LiveServerState.none
          when herdrError is String && herdrError.contains('not installed'):
        return HomeBoardState(
          phase: HomeBoardPhase.notInstalled,
          tmux: tmuxStatus,
          tmuxSessions: tmuxSessions,
          message: 'Herdr is not installed on this machine.',
          updatedAt: now,
        );
      case LiveServerState.none || LiveServerState.down:
        return HomeBoardState(
          phase: HomeBoardPhase.notRunning,
          tmux: tmuxStatus,
          tmuxSessions: tmuxSessions,
          message: 'Herdr is not running on this machine.',
          updatedAt: now,
        );
      case LiveServerState.unknown || LiveServerState.off:
        return HomeBoardState(
          phase: HomeBoardPhase.loading,
          tmux: tmuxStatus,
          tmuxSessions: tmuxSessions,
          updatedAt: now,
        );
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) {
      if (_skipTicks > 0) {
        _skipTicks -= 1;
        return;
      }
      unawaited(_fetch());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _closeRunner() async {
    final runner = _runner;
    _runner = null;
    if (runner != null) {
      try {
        await runner.close();
      } catch (_) {
        // Already gone.
      }
    }
  }

  /// Runs one listing for the current machine. Visible for tests so they
  /// can drive polls without timers.
  @visibleForTesting
  Future<void> pollNow() => _fetch();

  Future<void> _fetch() async {
    final host = _host;
    if (_disposed ||
        _fetchingGeneration == _generation ||
        host == null ||
        !_listable ||
        _needsRequest) {
      return;
    }
    final generation = _generation;
    _fetchingGeneration = generation;
    final before = _state;
    if (_state.phase != HomeBoardPhase.loading && !_state.refreshing) {
      // Nothing draws the flag: no rebuild for it.
      _state = _state.copyWith(refreshing: true);
    }
    try {
      final runner = _runner ??= _runnerFactory(host);
      final next = await _load(runner);
      if (_disposed || generation != _generation) return;
      _state = next;
      _failures = 0;
      _quietPolls = next.sameBoardAs(before) ? _quietPolls + 1 : 0;
      _skipTicks = (_quietPolls ~/ _quietPollsPerStep).clamp(0, _maxQuietSkip);
      if (_nothingToPoll) {
        // No point polling a machine without tmux or Herdr; pull-to-refresh
        // or switching machines tries again.
        _stopTimer();
      }
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _failures += 1;
      _skipTicks = _failures.clamp(0, _maxBackoffTicks);
      if (_failures >= _maxFailures) {
        _stopTimer();
      }
      _state = HomeBoardState(
        phase: HomeBoardPhase.failed,
        workspaces: _state.workspaces,
        tmux: _state.tmux,
        tmuxSessions: _state.tmuxSessions,
        backend: host.backend,
        hcTerminals: _state.hcTerminals,
        message: error is AppFailure ? error.toString() : '$error',
        problem: connectionProblemFor(
          error,
          machine: host.name,
          address: host.host,
        ),
        updatedAt: _state.updatedAt,
      );
      // A broken channel reconnects on the next poll.
      unawaited(_closeRunner());
    } finally {
      if (_fetchingGeneration == generation) {
        _fetchingGeneration = null;
      }
      // A refresh while the board is hidden (the quick switcher, a sync
      // pull) must not leave its channel open in the background.
      if (!_disposed && !_visible) unawaited(_closeRunner());
      // A poll that lists what is on screen (most of them) rebuilds
      // nothing.
      if (!_disposed &&
          generation == _generation &&
          !_state.sameBoardAs(before)) {
        notifyListeners();
      }
    }
  }

  Future<HomeBoardState> _load(AgentCommandRunner runner) async {
    final tools = _host?.tools ?? const <HostTool>{};
    final (tmux, tmuxSessions) = tools.contains(HostTool.tmux)
        ? await _loadTmux(runner)
        : (HomeTmuxStatus.unknown, const <TmuxSessionInfo>[]);
    final hc = tools.contains(HostTool.herdrApp);
    final herdr = tools.contains(HostTool.herdr);
    if (hc && !herdr) return _loadHc(runner, tmux, tmuxSessions);
    if (!hc && !herdr) {
      return HomeBoardState(
        phase: HomeBoardPhase.notInstalled,
        tmux: tools.contains(HostTool.tmux) ? tmux : HomeTmuxStatus.available,
        tmuxSessions: tmuxSessions,
        updatedAt: DateTime.now(),
      );
    }
    if (!hc) return _loadHerdr(runner, tmux, tmuxSessions);
    // Both: each lists what it can; one being down keeps the other.
    final app = await _loadHc(
      runner,
      HomeTmuxStatus.available,
      tmuxSessions,
    ).then<HomeBoardState?>((state) => state, onError: (Object _) => null);
    final HomeBoardState? tui;
    try {
      tui = await _loadHerdr(runner, tmux, tmuxSessions);
    } catch (_) {
      if (app == null) rethrow;
      return app.copyWith(tmux: tmux);
    }
    if (app == null || app.phase != HomeBoardPhase.ready) return tui;
    return app.copyWith(
      tmux: tmux,
      workspaces: [...tui.workspaces, ...app.workspaces],
    );
  }

  Future<(HomeTmuxStatus, List<TmuxSessionInfo>)> _loadTmux(
    AgentCommandRunner runner,
  ) async {
    final tmuxResult = await runner.run(
      RemoteSessionListing.tmuxListCommand,
      timeout: _timeout,
    );
    return switch (RemoteSessionListing.interpretTmux(tmuxResult)) {
      RemoteListingAvailable<TmuxSessionInfo>(:final items) => (
        HomeTmuxStatus.available,
        items,
      ),
      RemoteListingNotInstalled<TmuxSessionInfo>() => (
        HomeTmuxStatus.notInstalled,
        const <TmuxSessionInfo>[],
      ),
      RemoteListingNotRunning<TmuxSessionInfo>() => (
        HomeTmuxStatus.available,
        const <TmuxSessionInfo>[],
      ),
      RemoteListingFailed<TmuxSessionInfo>() => (
        HomeTmuxStatus.failed,
        const <TmuxSessionInfo>[],
      ),
    };
  }

  /// The board from the herdr CLI, with the tmux side already listed.
  Future<HomeBoardState> _loadHerdr(
    AgentCommandRunner runner,
    HomeTmuxStatus tmux,
    List<TmuxSessionInfo> tmuxSessions,
  ) async {
    final workspaceResult = await runner.run(
      RemoteSessionListing.herdrWorkspaceListCommand,
      timeout: _timeout,
    );
    final listing = RemoteSessionListing.interpretHerdrWorkspaces(
      workspaceResult,
    );
    switch (listing) {
      case RemoteListingNotInstalled<HerdrWorkspaceInfo>():
        return HomeBoardState(
          phase: HomeBoardPhase.notInstalled,
          tmux: tmux,
          tmuxSessions: tmuxSessions,
          message: 'Herdr is not installed on this machine.',
          updatedAt: DateTime.now(),
        );
      case RemoteListingNotRunning<HerdrWorkspaceInfo>(:final message):
        return HomeBoardState(
          phase: HomeBoardPhase.notRunning,
          tmux: tmux,
          tmuxSessions: tmuxSessions,
          message: message,
          updatedAt: DateTime.now(),
        );
      case RemoteListingFailed<HerdrWorkspaceInfo>(:final message):
        if (tmux == HomeTmuxStatus.available) {
          // tmux answered, so the machine is reachable: Herdr alone is
          // broken. Keep the tmux side on screen.
          return HomeBoardState(
            phase: HomeBoardPhase.failed,
            workspaces: _state.workspaces,
            tmux: tmux,
            tmuxSessions: tmuxSessions,
            message: message,
            updatedAt: DateTime.now(),
          );
        }
        throw AppFailure(message);
      case RemoteListingAvailable<HerdrWorkspaceInfo>(:final items):
        final tabs = await _loadTabs(runner);
        final agents = await _loadAgents(runner);
        return HomeBoardState(
          phase: HomeBoardPhase.ready,
          workspaces: buildBoard(items, tabs, agents),
          tmux: tmux,
          tmuxSessions: tmuxSessions,
          updatedAt: DateTime.now(),
        );
    }
  }

  /// The Herdr app's spaces as workspaces, so the Projects view and the
  /// machine tree group hc agents the way they group Herdr's (CON-130):
  /// live terminals by the space they are in (its id when hc gives it, so
  /// two spaces both called "Projects" stay two, CON-135), else by the
  /// space name `where` gives, else by their folder. Ids
  /// are [hcWorkspaceId], stable across refreshes; their panes are the
  /// agents [HcAttentionProvider] reports, which open with `hc attach`.
  @visibleForTesting
  static List<HomeBoardWorkspace> hcWorkspaces(
    List<HcTerminalInfo> items, {
    Set<String> skipMachines = const {},
  }) {
    final bySpace = <String, List<HcTerminalInfo>>{};
    final labels = <String, String>{};
    // Space ids come with `terminal.list`; an `hc ls` listing has none.
    final withIds = items.any((terminal) => terminal.spaceId.isNotEmpty);
    for (final terminal in items.where((terminal) => terminal.live)) {
      if (skipMachines.contains(terminal.machine.toLowerCase())) continue;
      final space = terminal.space.isNotEmpty
          ? terminal.space
          : (terminal.folder.isNotEmpty ? terminal.folder : terminal.address);
      // A space may hold tabs of several machines: by name, without ids.
      // In a listing with ids, a terminal without one is in no app space
      // (`hc run` from a script): its own workspace, never matched by name.
      final key = terminal.spaceId.isNotEmpty
          ? terminal.spaceId
          : withIds
          ? 'loose:${terminal.machine}/$space'
          : 'name:$space';
      labels.putIfAbsent(key, () => space);
      bySpace.putIfAbsent(key, () => []).add(terminal);
    }
    return [
      for (final (index, MapEntry(key: key, value: terminals))
          in bySpace.entries.indexed)
        HomeBoardWorkspace(
          workspace: HerdrWorkspaceInfo(
            id: hcSpaceWorkspaceId(key, named: key.startsWith('name:')),
            label: labels[key]!,
            number: index + 1,
            agentStatus: _mostUrgent(terminals.map((t) => t.status)),
            tabCount: terminals.length,
          ),
          panes: [
            for (final agent in HcAttentionProvider.agentsOf(terminals))
              HomeBoardPane(agent: agent),
          ],
        ),
    ];
  }

  static String _mostUrgent(Iterable<String> statuses) {
    const order = ['blocked', 'done', 'working', 'idle'];
    for (final status in order) {
      if (statuses.contains(status)) return status;
    }
    return '';
  }

  /// The board of an hc machine: tmux as usual, then `hc ls` in place of
  /// the herdr CLI, so no herdr error or "Start Herdr" shows there.
  Future<HomeBoardState> _loadHc(
    AgentCommandRunner runner,
    HomeTmuxStatus tmux,
    List<TmuxSessionInfo> tmuxSessions,
  ) async {
    final result = await runner.run(HcCommands.list, timeout: _timeout);
    final base = HomeBoardState(
      backend: HostBackend.hc,
      tmux: tmux,
      tmuxSessions: tmuxSessions,
      updatedAt: DateTime.now(),
    );
    switch (HcListing.interpret(result)) {
      case RemoteListingAvailable<HcTerminalInfo>(:final items):
        return base.copyWith(
          phase: HomeBoardPhase.ready,
          hcTerminals: items,
          workspaces: hcWorkspaces(items, skipMachines: skipHcMachines),
        );
      case RemoteListingNotInstalled<HcTerminalInfo>():
        return base.copyWith(
          phase: HomeBoardPhase.notInstalled,
          message: 'hc (herdr-core) is not installed on this machine.',
        );
      case RemoteListingNotRunning<HcTerminalInfo>(:final message) ||
          RemoteListingFailed<HcTerminalInfo>(:final message):
        if (tmux != HomeTmuxStatus.available) throw AppFailure(message);
        return base.copyWith(
          phase: HomeBoardPhase.failed,
          hcTerminals: _state.hcTerminals,
          message: message,
        );
    }
  }

  Future<List<HerdrTabInfo>> _loadTabs(AgentCommandRunner runner) async {
    try {
      final result = await runner.run(
        RemoteSessionListing.herdrTabListCommand,
        timeout: _timeout,
      );
      if (result.exitCode != null && result.exitCode != 0) return const [];
      return RemoteSessionListing.parseHerdrTabs(result.stdout);
    } on AppFailure {
      rethrow;
    } catch (_) {
      // Tab labels are a nicety; the board still shows workspaces.
      return const [];
    }
  }

  Future<List<AgentInfo>> _loadAgents(AgentCommandRunner runner) async {
    try {
      final snapshot = await _provider.fetchAgents(runner);
      return snapshot.agents;
    } on AgentProviderUnavailable {
      // An older Herdr without `agent list`: workspaces only.
      return const [];
    }
  }

  /// Groups [agents] under their [workspaces], resolving tab labels, and
  /// gives each workspace its [tabs].
  /// Agents whose workspace is not listed are dropped; workspace order is
  /// Herdr's; panes are ordered by tab number, then pane id.
  static List<HomeBoardWorkspace> buildBoard(
    List<HerdrWorkspaceInfo> workspaces,
    List<HerdrTabInfo> tabs,
    List<AgentInfo> agents,
  ) {
    final tabsById = {for (final tab in tabs) tab.id: tab};
    return [
      for (final workspace in workspaces)
        HomeBoardWorkspace(
          // The workspace's tabs in Herdr's order, for the desktop sidebar.
          workspace: workspace.tabs.isNotEmpty
              ? workspace
              : workspace.withTabs(
                  [
                    for (final tab in tabs)
                      if (tab.workspaceId == workspace.id) tab,
                  ]..sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0)),
                ),
          panes:
              [
                for (final agent in agents)
                  if (agent.workspace == workspace.id)
                    HomeBoardPane(
                      agent: agent,
                      tabLabel: _tabLabel(tabsById[agent.tab]),
                    ),
              ]..sort((a, b) {
                final byTab = (tabsById[a.agent.tab]?.number ?? 0).compareTo(
                  tabsById[b.agent.tab]?.number ?? 0,
                );
                if (byTab != 0) return byTab;
                return (a.agent.pane ?? a.agent.id).compareTo(
                  b.agent.pane ?? b.agent.id,
                );
              }),
        ),
    ];
  }

  static String _tabLabel(HerdrTabInfo? tab) {
    if (tab == null) return '';
    if (tab.label.isNotEmpty) return tab.label;
    return tab.number == null ? '' : 'Tab ${tab.number}';
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    _detachFeed();
    unawaited(_closeRunner());
    super.dispose();
  }
}

/// A machine the home page lists, and whether the app reached it before
/// (see [HomeBoardController.selectHost]).
@immutable
class HomeBoardEntry {
  const HomeBoardEntry(this.host, {this.connectedBefore = false});

  final SavedHost host;
  final bool connectedBefore;
}

/// One [HomeBoardController] per machine the home page shows (the machine
/// filter's selection), created and disposed as the selection changes.
///
/// Every board keeps its own rules (on-screen polling, one fetch at a time,
/// failure backoff, hardware-key and never-connected machines waiting for a
/// request); this set only fans visibility and refreshes out to them and
/// forwards their changes.
class HomeBoards extends ChangeNotifier {
  HomeBoards({
    required AgentCommandRunnerFactory runnerFactory,
    AgentAttentionProvider provider = const HerdrAttentionProvider(),
    Duration pollInterval = const Duration(seconds: 5),
    LiveHostFeed? Function(SavedHost host)? liveFeed,
  }) : _create = (() => HomeBoardController(
         runnerFactory: runnerFactory,
         provider: provider,
         pollInterval: pollInterval,
         liveFeed: liveFeed,
       ));

  final HomeBoardController Function() _create;
  final Map<String, HomeBoardController> _boards = {};
  bool _visible = false;
  bool _disposed = false;

  bool get visible => _visible;

  /// Machine ids with a board, in selection order.
  Iterable<String> get hostIds => _boards.keys;

  /// The board of machine [hostId], if it is selected.
  HomeBoardController? operator [](String hostId) => _boards[hostId];

  /// Boards for exactly [entries] (local machines are skipped): new
  /// machines start listing, dropped ones stop and close their channel.
  void sync(List<HomeBoardEntry> entries) {
    if (_disposed) return;
    final wanted = {
      for (final entry in entries)
        if (!entry.host.isLocal) entry.host.id: entry,
    };
    var changed = false;
    for (final id in List.of(_boards.keys)) {
      if (!wanted.containsKey(id)) {
        _boards.remove(id)!
          ..removeListener(notifyListeners)
          ..dispose();
        changed = true;
      }
    }
    for (final entry in wanted.values) {
      var board = _boards[entry.host.id];
      if (board == null) {
        board = _create()..addListener(notifyListeners);
        _boards[entry.host.id] = board;
        changed = true;
        board.setVisible(_visible);
      }
      board.skipHcMachines = {
        for (final other in wanted.values)
          if (other.host.id != entry.host.id &&
              other.host.backend == HostBackend.hc)
            other.host.name.toLowerCase(),
      };
      board.selectHost(entry.host, connectedBefore: entry.connectedBefore);
    }
    if (changed) notifyListeners();
  }

  /// Starts or stops every board's polling.
  void setVisible(bool visible) {
    if (_disposed || visible == _visible) return;
    _visible = visible;
    for (final board in List.of(_boards.values)) {
      board.setVisible(visible);
    }
  }

  /// Fetches every board now.
  Future<void> refresh() async {
    await Future.wait([
      for (final board in List.of(_boards.values)) board.refresh(),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final board in _boards.values) {
      board
        ..removeListener(notifyListeners)
        ..dispose();
    }
    _boards.clear();
    super.dispose();
  }
}
