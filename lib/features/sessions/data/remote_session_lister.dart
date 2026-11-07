import 'package:conduit/core/app_failure.dart';
import 'package:conduit/features/agent_attention/domain/agent_command_runner.dart';
import 'package:conduit/features/desktop_shell/domain/hc_documents.dart';
import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/sessions/domain/hc_terminals.dart';
import 'package:conduit/features/sessions/domain/remote_session_listing.dart';

/// Lists tmux sessions and Herdr workspaces on a host over an
/// [AgentCommandRunner] (a dedicated SSH exec channel, never the PTY).
class RemoteSessionLister {
  const RemoteSessionLister(this._runner);

  static const _timeout = Duration(seconds: 10);

  final AgentCommandRunner _runner;

  Future<RemoteListing<TmuxSessionInfo>> listTmux() async {
    try {
      final result = await _runner.run(
        RemoteSessionListing.tmuxListCommand,
        timeout: _timeout,
      );
      return RemoteSessionListing.interpretTmux(result);
    } on AppFailure catch (failure) {
      return RemoteListingFailed(failure.toString(), error: failure);
    } catch (error) {
      return RemoteListingFailed(error.toString(), error: error);
    }
  }

  /// Lists Herdr workspaces. With one Herdr session running (the usual
  /// case) its workspaces are listed as they are; with several named
  /// sessions each workspace carries its session, shown as
  /// "session ‧ workspace".
  Future<RemoteListing<HerdrWorkspaceInfo>> listHerdr() async {
    final sessions = await _runningHerdrSessions();
    if (sessions == null || sessions.length <= 1) {
      return _listHerdrSession(sessions?.singleOrNull?.cliName ?? '');
    }
    final items = <HerdrWorkspaceInfo>[];
    RemoteListing<HerdrWorkspaceInfo>? firstProblem;
    for (final session in sessions) {
      final listing = await _listHerdrSession(
        session.cliName,
        sessionLabel: session.name,
      );
      if (listing is RemoteListingAvailable<HerdrWorkspaceInfo>) {
        items.addAll(listing.items);
      } else {
        firstProblem ??= listing;
      }
    }
    if (items.isEmpty && firstProblem != null) {
      return firstProblem;
    }
    return RemoteListingAvailable(items);
  }

  /// Running Herdr sessions, or null when `herdr session list` is not
  /// available (older Herdr, not installed); the default session is then
  /// listed alone.
  Future<List<HerdrSessionInfo>?> _runningHerdrSessions() async {
    try {
      final result = await _runner.run(
        RemoteSessionListing.herdrSessionListCommand,
        timeout: _timeout,
      );
      if (result.exitCode != null && result.exitCode != 0) {
        return null;
      }
      return RemoteSessionListing.parseHerdrSessions(
        result.stdout,
      )?.where((session) => session.running).toList();
    } catch (_) {
      return null;
    }
  }

  Future<RemoteListing<HerdrWorkspaceInfo>> _listHerdrSession(
    String session, {
    String sessionLabel = '',
  }) async {
    try {
      final result = await _runner.run(
        RemoteSessionListing.herdrWorkspaceListFor(session),
        timeout: _timeout,
      );
      var listing = RemoteSessionListing.interpretHerdrWorkspaces(result);
      if (listing is RemoteListingAvailable<HerdrWorkspaceInfo> &&
          (session.isNotEmpty || sessionLabel.isNotEmpty)) {
        listing = RemoteListingAvailable([
          for (final workspace in listing.items)
            workspace.inSession(session, sessionLabel: sessionLabel),
        ]);
      }
      if (listing is! RemoteListingAvailable<HerdrWorkspaceInfo> ||
          listing.items.every((workspace) => workspace.tabCount <= 1)) {
        return listing;
      }
      // Tab labels are a nicety: a failure here must not hide workspaces.
      try {
        final tabs = await _runner.run(
          RemoteSessionListing.herdrTabListFor(session),
          timeout: _timeout,
        );
        if (tabs.exitCode == 0) {
          var parsed = RemoteSessionListing.parseHerdrTabs(tabs.stdout);
          // What each tab shows, so no row has to fall back on an id.
          try {
            final panes = await _runner.run(
              RemoteSessionListing.herdrPaneListFor(session),
              timeout: _timeout,
            );
            if (panes.exitCode == 0) {
              parsed = RemoteSessionListing.attachPanes(parsed, panes.stdout);
            }
          } catch (_) {
            // Tabs keep their labels and pane counts.
          }
          return RemoteListingAvailable(
            RemoteSessionListing.attachTabs(listing.items, parsed),
          );
        }
      } catch (_) {
        // Fall through with workspaces only.
      }
      return listing;
    } on AppFailure catch (failure) {
      return RemoteListingFailed(failure.toString(), error: failure);
    } catch (error) {
      return RemoteListingFailed(error.toString(), error: error);
    }
  }

  /// Lists herdr-core terminals with `hc ls --json` (CON-100000).
  Future<RemoteListing<HcTerminalInfo>> listHc() async {
    try {
      final result = await _runner.run(HcCommands.ls, timeout: _timeout);
      return HcListing.interpret(result);
    } on AppFailure catch (failure) {
      return RemoteListingFailed(failure.toString(), error: failure);
    } catch (error) {
      return RemoteListingFailed(error.toString(), error: error);
    }
  }

  /// sheprd's view and cards from the machine's herdr-core documents, for
  /// grouping and labelling hc terminals. Both are optional: a machine
  /// without sheprd's mods, or a failed read, gives an empty result and
  /// the picker lists terminals ungrouped.
  Future<HcSheprdDocuments> readHcDocuments({
    Set<String> machines = const {},
  }) async {
    final on = machines.where((machine) => machine.isNotEmpty).toList()..sort();
    // This host first, then the machines it reaches in one more call, so a
    // machine that is down cannot cost this host's documents.
    final answers = await _docAnswers();
    final remote = on.isEmpty ? const <int, Object?>{} : await _docAnswers(on);
    // The view of the first machine that has one: this host's, else the
    // Herdr app's hub it reaches. Cards come from every machine, each
    // keeping its own agents'.
    HcSheprdView? view;
    final cards = <String, List<HcCard>>{};
    for (final (round, hub) in ['', ...on].indexed) {
      final from = round == 0 ? answers : remote;
      final id = round == 0 ? 0 : (round - 1) * 2;
      final scope = HcKeyScope(hub: hub, machines: machines);
      view ??= HcSheprdView.fromJson(from[id + 1])?.scoped(scope);
      for (final MapEntry(:key, :value) in HcCards.byTerminal(
        from[id + 2],
        scope: scope,
      ).entries) {
        cards.putIfAbsent(key, () => []).addAll(value);
      }
    }
    return HcSheprdDocuments(view: view, cards: cards);
  }

  /// `doc.get` answers for the view and the cards, on this host or on each
  /// of [on]; none when the call fails.
  Future<Map<int, Object?>> _docAnswers([List<String>? on]) async {
    try {
      final result = await _runner.run(
        on == null
            ? HcCommands.docGet(const [HcDocuments.view, HcDocuments.cards])
            : HcCommands.docGet(
                const [HcDocuments.view, HcDocuments.cards],
                on: on,
                skipLocal: true,
              ),
        timeout: _timeout,
      );
      if (result.exitCode != null && result.exitCode != 0) return const {};
      return HcListing.parseDocAnswers(result.stdout);
    } catch (_) {
      return const {};
    }
  }

  /// What is installed for [HostBackend.suggest]: the default backend when
  /// the probe fails.
  Future<HostBackend> suggestBackend() async {
    try {
      final result = await _runner.run(HcCommands.probe, timeout: _timeout);
      return HcCommands.suggestFromProbe(result.stdout);
    } catch (_) {
      return HostBackend.herdr;
    }
  }
}
