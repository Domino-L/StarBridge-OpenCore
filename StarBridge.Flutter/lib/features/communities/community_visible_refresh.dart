import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../platform/window/native_viewport_visibility.dart';

/// Bounded readback on the visible organization surface. Not a notification
/// subscription: background organization messages have their own lifecycle.
mixin CommunityVisibleRefresh<T extends StatefulWidget> on State<T> {
  Timer? _visibleRefresh;
  AppLifecycleListener? _lifecycle;
  Future<void> refreshVisibleCommunity();
  Duration get communityRefreshInterval => const Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: refreshCommunityIfVisible);
    _visibleRefresh = Timer.periodic(communityRefreshInterval, (_) {
      refreshCommunityIfVisible();
    });
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
    unawaited(refreshVisibleCommunity());
  }

  @override
  void dispose() {
    _visibleRefresh?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
