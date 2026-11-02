import 'package:flutter/foundation.dart';

enum DeviceReviewSection { application, overlay, notifications, playReminder }

enum DeviceReviewState {
  unavailable,
  needsIdentity,
  contextChanged,
  settingsChanged,
  choicesRequired,
  reviewRequired,
  reviewed,
}

/// Device review is distinct from collection consent and functional readiness.
/// Values are immutable Host projections, never Flutter-owned saved settings.
@immutable
final class DeviceReviewSnapshot {
  const DeviceReviewSnapshot({
    this.state = DeviceReviewState.unavailable,
    this.reviewKey,
    this.sections = const {},
  });
  final DeviceReviewState state;
  final String? reviewKey;
  final Map<DeviceReviewSection, Map<String, Object?>?> sections;
  bool get canReview =>
      reviewKey != null &&
      const {
        DeviceReviewState.reviewRequired,
        DeviceReviewState.reviewed,
      }.contains(state);
}

abstract interface class DeviceReviewPort {
  Stream<void> get invalidations;
  Future<DeviceReviewSnapshot> read();
  Future<DeviceReviewSnapshot> confirm(
    String reviewKey,
    Set<DeviceReviewSection> sections,
  );
}
