import 'dart:async';

import '../../shared/diagnostics/loading_metrics.dart';

enum LoadingTourSelection { workspace, secondary, blocked }

/// An independent window the tour may open and hide. [close] must hide only:
/// the auxiliary engine stays alive, exactly as when the user closes it.
final class LoadingTourWindow {
  const LoadingTourWindow({required this.open, required this.close});
  final Future<bool> Function() open;
  final Future<void> Function() close;
}

typedef LoadingTourNavigate = Future<LoadingTourSelection> Function(
  String route,
);

/// Internal, explicit opt-in only. Routes pass through the normal leave guards.
/// No fields, commands, joins, publication or consent choices are submitted.
/// A blocked selection stops the tour and leaves its guard visible to the user.
final class LoadingTour {
  LoadingTour(
    this.metrics, {
    Future<void> Function(Duration)? wait,
    this.shellVisible,
    this.shellVisibleLimit = const Duration(seconds: 60),
  }) : _wait = wait ?? Future<void>.delayed;
  final LoadingMetrics metrics;
  final Future<void> Function(Duration) _wait;
  // Since DL-131 the shell is built offstage behind the startup screen. Page
  // timers start only once it is shown; the limit keeps a stalled startup from
  // holding the tour forever.
  final Future<void>? shellVisible;
  final Duration shellVisibleLimit;
  Future<void>? _completion;
  Future<void> get completion => _completion ?? Future<void>.value();
  LoadingTourNavigate? _navigate;
  bool _started = false, _stopped = false;
  int _binding = 0;

  static const primaryRoutes = [
    '/hangar',
    '/profile',
    '/communities',
    '/rooms',
    '/fleet',
    '/achievements',
    '/overlay',
    '/settings',
    '/settings/account',
    '/settings/privacy',
    '/tools',
    '/tools/exec-hangar',
    '/operations',
    '/marketplace',
    '/',
  ];

  // 2026-10-21 user report: the friends, messages and notifications windows
  // stall on open. After the pages, each window is opened and hidden three
  // times: the first opening creates its engine, later ones reuse it. The
  // auxiliary engines write their own traces; the primary trace records the
  // request (auxiliaryOpening) and these tour markers.
  static const windowKinds = ['friends', 'messages', 'notifications'];
  static const windowOpenings = 3;
  static const windowDwell = Duration(seconds: 6);
  static const windowGap = Duration(seconds: 2);
  final _windows = <String, LoadingTourWindow>{};

  void Function() registerWindow(String kind, LoadingTourWindow window) {
    _windows[kind] = window;
    return () {
      if (identical(_windows[kind], window)) _windows.remove(kind);
    };
  }

  void stop() => _stopped = true;

  void Function() bind(LoadingTourNavigate navigate) {
    final binding = ++_binding;
    _navigate = navigate;
    if (!_started) {
      _started = true;
      _completion = _run(binding);
      unawaited(_completion);
    }
    return () {
      if (_binding == binding) {
        _navigate = null;
        _stopped = true;
      }
    };
  }

  Future<void> _run(int binding) async {
    final visible = shellVisible;
    if (visible != null) {
      await visible.timeout(shellVisibleLimit, onTimeout: () {});
    }
    // Let the first visible shell frame and its normal prompt queue run first.
    await _wait(const Duration(seconds: 2));
    if (_stopped || metrics.stopped || binding != _binding) return;
    metrics.tour(LoadingTourPhase.begin);
    for (var round = 1; round <= 2; round++) {
      for (final route in primaryRoutes) {
        if (_stopped || metrics.stopped || binding != _binding) return;
        metrics.tour(LoadingTourPhase.navigate, route: route, round: round);
        LoadingTourSelection result;
        try {
          result = await _navigate!(route).timeout(const Duration(seconds: 15));
        } catch (_) {
          result = LoadingTourSelection.blocked;
        }
        if (_stopped || metrics.stopped || binding != _binding) return;
        if (result != LoadingTourSelection.workspace) {
          metrics.tour(LoadingTourPhase.blocked, route: route, round: round);
          stop();
          return;
        }
        final deadline = metrics.nowUs() + 15000000;
        var settled = false;
        while (!_stopped && !metrics.stopped && metrics.nowUs() < deadline) {
          final visit = metrics.visitFor(route);
          final content = visit == null
              ? null
              : metrics.renderedFor(route, visit);
          if (content != null &&
              content.status != LoadingContentStatus.waiting &&
              content.status != LoadingContentStatus.partial &&
              metrics.pendingPageReadsFor(visit!) == 0 &&
              metrics.nowUs() - content.us >= 1500000) {
            settled = true;
            break;
          }
          await _wait(const Duration(milliseconds: 250));
        }
        if (_stopped || metrics.stopped) return;
        metrics.tour(
          settled ? LoadingTourPhase.settled : LoadingTourPhase.timeout,
          route: route,
          round: round,
        );
      }
    }
    if (!await _visitWindows(binding)) return;
    metrics.tour(LoadingTourPhase.complete);
  }

  // Rounds 3–5 are the first, second and third opening of each window.
  Future<bool> _visitWindows(int binding) async {
    bool current() => !_stopped && !metrics.stopped && binding == _binding;
    for (final kind in windowKinds) {
      for (var opening = 1; opening <= windowOpenings; opening++) {
        final window = _windows[kind];
        if (!current()) return false;
        if (window == null) break;
        final route = '/$kind', round = 2 + opening;
        metrics.tour(LoadingTourPhase.navigate, route: route, round: round);
        bool shown;
        try {
          shown = await window.open().timeout(const Duration(seconds: 15));
        } catch (_) {
          shown = false;
        }
        if (!current()) return false;
        if (shown) await _wait(windowDwell);
        if (!current()) return false;
        metrics.tour(
          shown ? LoadingTourPhase.settled : LoadingTourPhase.timeout,
          route: route,
          round: round,
        );
        try {
          await window.close().timeout(const Duration(seconds: 5));
        } catch (_) {
          // A window that cannot hide still lets the tour finish.
        }
        await _wait(windowGap);
      }
    }
    return current();
  }
}
