import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/account/account_module.dart';
import '../../features/onboarding/connection_mode_controller.dart';
import 'startup_first_content.dart';

/// One lifecycle lease over the original read owners. No auth, mode write,
/// persistence or independent readiness state is introduced here.
final class StartupReadinessBinding {
  StartupReadinessBinding({
    required this.account,
    required this.mode,
    required this.current,
    required this.onChanged,
    this.firstContent = const [],
    this.firstContentLimit = StartupFirstContentLimit.safety,
  }) {
    account.projection.addListener(_changed);
    mode?.addListener(_changed);
    for (final item in firstContent) {
      item.listenable.addListener(_changed);
    }
  }
  final AccountModule account;
  final ConnectionModeController? mode;
  final bool Function() current;
  final VoidCallback onChanged;
  final List<StartupFirstContentItem> firstContent;
  final Duration firstContentLimit;
  bool _disposed = false;
  Timer? _limit;
  bool _limitReached = false;

  /// True once every first-glance item is settled, or the safety limit has
  /// passed since the account was first observed signed in.
  bool get firstContentSettled {
    if (_limitReached) return true;
    if (firstContent.every((item) => item.settled())) {
      _limit?.cancel();
      return true;
    }
    final value = account.projection.value;
    if (_limit == null && (value.isSignedIn || value.isLegacyAccount)) {
      _limit = Timer(firstContentLimit, () {
        _limitReached = true;
        _changed();
      });
    }
    return false;
  }

  void _changed() {
    if (!_disposed && current()) onChanged();
  }

  Future<void> retry() async {
    if (_disposed || !current()) return;
    await mode?.refresh();
    if (!_disposed && current() && (mode?.allowsOnlineTraffic ?? true)) {
      await account.refresh();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _limit?.cancel();
    account.projection.removeListener(_changed);
    mode?.removeListener(_changed);
    for (final item in firstContent) {
      item.listenable.removeListener(_changed);
    }
  }
}
