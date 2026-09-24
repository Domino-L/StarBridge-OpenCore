import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/settings/local_privacy_controller.dart';
import '../presence/manual_presence.dart';

/// App-level projection: observes saved consent/status, never publishes.
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

  String? _project() {
    if (controller.status != LocalPrivacyStatus.ready ||
        !controller.savedPublicationEnabled ||
        !controller.publicationObserved ||
        presence?.snapshot.confirmedMode == PresenceVisibility.invisible) {
      return null;
    }
    return switch (controller.publicationView.state) {
      'applied'
          when controller.publicationView.revision == controller.revision =>
        null,
      'failed' || 'withdrawalPending' => 'failed',
      'identityRequired' => 'identity',
      'withdrawn' => 'paused',
      _ => 'waiting',
    };
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
    if (issue == 'waiting') {
      _grace ??= Timer(const Duration(seconds: 15), () {
        if (_disposed) return;
        _overdue = true;
        _changed();
      });
    } else {
      _clearGrace();
    }
    // ValueNotifier emits only real changes: polling does not re-announce a strip.
    value = issue == 'waiting' && !_overdue ? null : issue;
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
