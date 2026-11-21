import '../../platform/bridge/bridge_envelope.dart';

/// Account observations are independent of the owner's local time counter.
/// Missing data is unknown; a confirmed zero must remain distinguishable.
int? profileGameplayMinutes(Map<String, Object?>? statistics) {
  final seconds = statistics?['playTimeSeconds'];
  if (seconds == null) return null;
  if (seconds is! int || seconds < 0) {
    throw const BridgeFormatException(
      'gameplayStatistics.playTimeSeconds must be a non-negative integer.',
    );
  }
  return seconds ~/ 60;
}

// Hong Kong's absent-record sentinel is revision zero AND Instant.EPOCH.
// Missing/invalid dates never establish absence.
bool profileNeverSaved(Map<String, Object?> profile) {
  final updatedAt = profile['updatedAt'];
  return profile['revision'] == 0 &&
      updatedAt is String &&
      DateTime.tryParse(updatedAt)?.toUtc() ==
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
