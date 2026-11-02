import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/settings/local_privacy_controller.dart';
import '../../features/settings/sharing_status_presentation.dart';
import '../presence/manual_presence.dart';

enum SharingIndicatorState { sharing, closed, stopping, unknown }

/// App-level projection; polling never publishes. Retry requires a user action.
/// Shell chrome consumes only this read model, not settings implementation.
class SharingStatusMonitor extends ValueNotifier<String?> {
  static const _identityIssues = {'identity', 'identityPending'};
  SharingStatusMonitor({required this.controller, this.presence})
    : super(null) {
    controller.addListener(_changed);
    presence?.addListener(_changed);
    scheduleMicrotask(() {
      if (_disposed) return;
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
  bool _offline = false;
  bool get isOffline => presence?.isOffline ?? false;
  SharingIndicatorState _indicator = SharingIndicatorState.unknown;
  SharingIndicatorState get indicator => _indicator;

  // A preference, presence mode or successful settings save is not a receipt.
  SharingIndicatorState _projectIndicator() {
    if (controller.status != LocalPrivacyStatus.ready ||
        !controller.hasSaved ||
        !controller.publicationObserved ||
        controller.publicationReadFailures > 0) {
      return SharingIndicatorState.unknown;
    }
    return switch (controller.publicationView.state) {
      'applied' => SharingIndicatorState.sharing,
      'withdrawn' => SharingIndicatorState.closed,
      'withdrawalPending' => SharingIndicatorState.stopping,
      _ => SharingIndicatorState.unknown,
    };
  }

  bool get canRetry =>
      !isOffline &&
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
    if (isOffline ||
        controller.status != LocalPrivacyStatus.ready ||
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
    // A deliberate offline choice is not a failed publication observation.
    // Release this chrome's read lease without changing the saved consent.
    if (isOffline) {
      _release?.call();
      _release = null;
    } else if (_release == null) {
      // refresh() may notify synchronously while acquiring the shared lease.
      _release = () {};
      _release = controller.monitorPublication();
    }
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
    // The Host retries every few seconds while identity is unconfirmed. Each
    // attempt reads as publishing and must not hide the strip, or it blinks.
    final hold = issue == 'waiting' && _identityIssues.contains(value);
    final next = delayed && !_overdue ? (hold ? value : null) : issue;
    final indicator = _projectIndicator();
    final actionChanged =
        _retryAvailable != canRetry ||
        _indicator != indicator ||
        _offline != isOffline;
    _offline = isOffline;
    _indicator = indicator;
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
