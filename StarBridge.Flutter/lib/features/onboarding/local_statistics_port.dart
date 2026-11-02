import 'package:flutter/foundation.dart';

enum LocalStatisticsState {
  unavailable,
  inactive,
  needsIdentity,
  choiceRequired,
  retryRequired,
  saved,
}

enum LocalStatisticsConsent { unknown, allowed, declined }

@immutable
final class LocalStatisticsSnapshot {
  const LocalStatisticsSnapshot({
    this.state = LocalStatisticsState.unavailable,
    this.choiceKey,
    this.consent = LocalStatisticsConsent.unknown,
    this.savedSeconds,
    this.recording = false,
  });
  final LocalStatisticsState state;
  final String? choiceKey;
  final LocalStatisticsConsent consent;
  final int? savedSeconds;
  final bool recording;
  bool get canChoose =>
      choiceKey != null &&
      const {
        LocalStatisticsState.choiceRequired,
        LocalStatisticsState.retryRequired,
        LocalStatisticsState.saved,
      }.contains(state);
  bool get choiceSaved =>
      state == LocalStatisticsState.saved &&
      consent != LocalStatisticsConsent.unknown;
}

abstract interface class LocalStatisticsPort {
  Stream<void> get invalidations;
  Future<LocalStatisticsSnapshot> read();
  Future<LocalStatisticsSnapshot> confirm(String choiceKey, bool allowed);
}
