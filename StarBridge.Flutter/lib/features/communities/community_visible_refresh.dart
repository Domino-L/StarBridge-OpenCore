import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../platform/window/native_viewport_visibility.dart';

/// Event-driven readback for capable surfaces; bounded reconciliation is only
/// the fallback for unavailable event transport. Hidden surfaces defer events.
/// Background organization message notifications have their own lifecycle.
mixin CommunityVisibleRefresh<T extends StatefulWidget> on State<T> {
  Timer? _visibleRefresh;
  Timer? _eventRefresh;
  StreamSubscription<void>? _changes;
  Stream<void>? get communityChanges => null;
  bool get communityEventsHealthy => false;
  bool _eventPending = false;
  AppLifecycleListener? _lifecycle;
  Future<void> refreshVisibleCommunity();
  Duration get communityRefreshInterval => const Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: refreshCommunityIfVisible);
    _visibleRefresh = Timer.periodic(communityRefreshInterval, (_) {
      if (!communityEventsHealthy || _eventPending) refreshCommunityIfVisible();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenToChanges();
    if (_eventPending) _queueEvent();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listenToChanges();
  }

  Stream<void>? _source;
  void _listenToChanges() {
    final source = communityChanges;
    if (identical(source, _source)) return;
    unawaited(_changes?.cancel());
    _source = source;
    _eventPending = false;
    _changes = source?.listen((_) {
      _eventPending = true;
      _queueEvent();
    });
  }

  void _queueEvent() {
    if (_eventRefresh?.isActive == true) return;
    _eventRefresh = Timer(
      const Duration(milliseconds: 120),
      refreshCommunityIfVisible,
    );
  }

  bool get isCommunityVisible {
    final state = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        state != null && state != AppLifecycleState.resumed ||
        !TickerMode.valuesOf(context).enabled ||
        !NativeViewportScope.isActive(context) ||
        nativeViewportMenus.value > 0 ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    return true;
  }

  void refreshCommunityIfVisible() {
    if (!isCommunityVisible) return;
    _eventPending = false;
    unawaited(refreshVisibleCommunity());
  }

  @override
  void dispose() {
    _visibleRefresh?.cancel();
    _eventRefresh?.cancel();
    unawaited(_changes?.cancel());
    _lifecycle?.dispose();
    super.dispose();
  }
}
