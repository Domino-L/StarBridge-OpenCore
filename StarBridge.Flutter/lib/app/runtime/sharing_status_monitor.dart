import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/settings/local_privacy_controller.dart';
import '../../features/settings/sharing_status_presentation.dart';
import '../presence/manual_presence.dart';

/// App-level projection; polling never publishes. Retry requires a user action.
/// Shell chrome consumes only this read model, not settings implementation.
class SharingStatusMonitor extends ValueNotifier<String?> {
  SharingStatusMonitor({required this.controller, this.presence})
    : super(null) {
    controller.addListener(_changed);
    presence?.addListener(_changed);
    scheduleMicrotask(() {
      if (_disposed) return;
      _release = controller.monitorPublication();
      _changed();
    });
  }
  final LocalPrivacyController controller;
  final ManualPresenceController? presence;
  VoidCallback? _release;
  Timer? _grace;
  bool _overdue = false, _disposed = false;
  int? _epoch;
  bool _retryAvailable = false;
  bool get canRetry =>
      (controller.publicationReadFailures >= 2 ||
          controller.canRetryPublication) &&
      !controller.publicationBusy &&
      controller.status == LocalPrivacyStatus.ready &&
      presence?.snapshot.confirmedMode != PresenceVisibility.invisible;
  Future<void> retry() async {
    if (_disposed || !canRetry) return;
    if (controller.publicationReadFailures >= 2) {
      await controller.refreshPublication();
    } else {
      await controller.applyPublication();
    }
  }

  String? _project() {
    if (controller.status != LocalPrivacyStatus.ready ||
        (!controller.savedPublicationEnabled &&
            controller.publicationView.state != 'withdrawalPending') ||
        presence?.snapshot.confirmedMode == PresenceVisibility.invisible) {
      return null;
    }
    if (controller.publicationReadFailures >= 2) return 'statusRead';
    if (!controller.publicationObserved) return null;
    return sharingStatusIssue(controller.publicationView, controller.revision);
  }

  void _clearGrace() {
    _grace?.cancel();
    _grace = null;
    _overdue = false;
  }

  void _changed() {
    if (_disposed) return;
    if (_epoch != controller.scopeEpoch) {
      _epoch = controller.scopeEpoch;
      _clearGrace();
    }
    final issue = _project();
    final delayed =
        issue == 'waiting' || recoveringSharingIssues.contains(issue);
    if (delayed) {
      _grace ??= Timer(Duration(seconds: issue == 'waiting' ? 15 : 30), () {
        if (_disposed) return;
        _overdue = true;
        _changed();
      });
    } else {
      _clearGrace();
    }
    // ValueNotifier emits only real changes: polling does not re-announce a strip.
    final next = delayed && !_overdue ? null : issue;
    final actionChanged = _retryAvailable != canRetry;
    _retryAvailable = canRetry;
    if (value == next) {
      if (actionChanged) notifyListeners();
    } else {
      value = next;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_changed);
    presence?.removeListener(_changed);
    _release?.call();
    _clearGrace();
    super.dispose();
  }
}
