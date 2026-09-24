import 'dart:async';

import 'package:flutter/widgets.dart';

/// Serializes automatic prompts at the root navigator. Manual routes always win.
/// Callers own persistence and account eligibility; this module owns timing.
final class StartupPromptQueue extends NavigatorObserver
    with WidgetsBindingObserver {
  StartupPromptQueue({this.quietPeriod = const Duration(milliseconds: 800)}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Duration quietPeriod;
  final Map<Object, _Prompt> _pending = {};
  final List<Route<dynamic>> _routes = [];
  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  bool get hasBlockingRoute => _routes.any((r) => r.isActive && !r.isFirst);
  bool get _foreground => switch (WidgetsBinding.instance.lifecycleState) {
    null || AppLifecycleState.resumed => true,
    _ => false,
  };

  void enqueue(
    Object key, {
    required int priority,
    required bool Function() eligible,
    required Future<void> Function() show,
  }) {
    if (_disposed) return;
    _pending[key] = _Prompt(priority, eligible, show);
    wake();
  }

  void cancel(Object key) {
    _pending.remove(key);
    wake();
  }

  void wake() {
    if (_disposed || _running || _timer != null || _pending.isEmpty) return;
    _timer = Timer(quietPeriod, _drain);
  }

  void _routeChanged() {
    _timer?.cancel();
    _timer = null;
    wake();
  }

  Future<void> _drain() async {
    _timer = null;
    if (_disposed ||
        _running ||
        !_foreground ||
        hasBlockingRoute ||
        navigator == null) {
      return;
    }
    final entries = _pending.entries.toList()
      ..sort((a, b) => a.value.priority.compareTo(b.value.priority));
    for (final entry in entries) {
      if (!entry.value.eligible()) continue;
      _pending.remove(entry.key);
      _running = true;
      try {
        await entry.value.show();
      } finally {
        _running = false;
        wake();
      }
      return;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) _routes.clear();
    _routes.add(route);
    _routeChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _routeChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _routeChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _routes.remove(oldRoute);
    if (newRoute != null) _routes.add(newRoute);
    _routeChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _routeChanged();

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _pending.clear();
    WidgetsBinding.instance.removeObserver(this);
  }
}

final class _Prompt {
  const _Prompt(this.priority, this.eligible, this.show);
  final int priority;
  final bool Function() eligible;
  final Future<void> Function() show;
}
