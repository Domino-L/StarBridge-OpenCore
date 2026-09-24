import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../platform/window/native_viewport_visibility.dart';
import 'community_announcements_controller.dart';

/// Matches the WPF announcement cadence without inventing a new transport:
/// visible time labels every two seconds, authorized readback every ten.
/// The entry and its modal share one controller; only the current route polls.
mixin CommunityAnnouncementsRefresh<T extends StatefulWidget> on State<T> {
  CommunityAnnouncementsController get announcementModel;
  Timer? _announcementTimer;
  var _announcementTicks = 0;

  @override
  void initState() {
    super.initState();
    _announcementTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!mounted ||
          !announcementModel.active ||
          lifecycle != null && lifecycle != AppLifecycleState.resumed ||
          !TickerMode.valuesOf(context).enabled ||
          !NativeViewportScope.isActive(context) ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      announcementModel.refreshTimeLabels();
      if (++_announcementTicks % 5 == 0 &&
          announcementModel.error != 'refreshRequired') {
        unawaited(announcementModel.refresh(background: true));
      }
    });
  }

  @override
  void dispose() {
    _announcementTimer?.cancel();
    super.dispose();
  }
}
