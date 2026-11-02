import 'dart:async';

import 'package:flutter/widgets.dart';

import '../communities/community_visible_refresh.dart';

/// A low-frequency silent members reconcile behind the pushed updates:
/// every five minutes while the workspace is visible (2026-10-29).
mixin OfficialFleetMembersFallback<T extends StatefulWidget>
    on CommunityVisibleRefresh<T> {
  Future<void> refreshMembers();
  Timer? _membersFallback;

  @override
  void initState() {
    super.initState();
    _membersFallback = Timer.periodic(const Duration(minutes: 5), (_) {
      if (isCommunityVisible) unawaited(refreshMembers());
    });
  }

  @override
  void dispose() {
    _membersFallback?.cancel();
    super.dispose();
  }
}
