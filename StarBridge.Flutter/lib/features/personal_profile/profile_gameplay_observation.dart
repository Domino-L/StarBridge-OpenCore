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
