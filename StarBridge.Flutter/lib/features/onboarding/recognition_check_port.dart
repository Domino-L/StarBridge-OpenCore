import 'package:flutter/foundation.dart';

/// One read of the confirmed local log slot (setup "is recognition working").
/// Observations only; nothing here enables listening or records anything.
@immutable
final class RecognitionCheckSnapshot {
  const RecognitionCheckSnapshot({
    required this.state,
    this.version,
    this.handle,
    this.serverState = 'unknown',
    this.serverRegion,
    this.locationState = 'unknown',
    this.locationEnglish,
    this.locationZhHans,
    this.shipState = 'unknown',
    this.shipEnglish,
    this.shipZhHans,
    this.shipZhHant,
  });
  final String state;
  final String? version, handle, serverRegion;
  final String serverState, locationState, shipState;
  final String? locationEnglish, locationZhHans;
  final String? shipEnglish, shipZhHans, shipZhHant;

  bool get ready => state == 'ready' && handle != null;
  bool get gameClosed =>
      const {'notRunning', 'processUnknown', 'otherSource'}.contains(state);
  bool get listeningOff => const {'choiceRequired', 'stopped'}.contains(state);
  bool get inactive => state == 'inactive';

  String? location(String language, String? country) =>
      language == 'zh' ? locationZhHans ?? locationEnglish : locationEnglish;

  String? ship(String language, String? country) {
    if (language != 'zh') return shipEnglish ?? shipZhHans;
    return const {'TW', 'HK', 'MO'}.contains(country)
        ? shipZhHant ?? shipZhHans ?? shipEnglish
        : shipZhHans ?? shipZhHant ?? shipEnglish;
  }
}

abstract interface class RecognitionCheckPort {
  bool get supported;
  Future<RecognitionCheckSnapshot> read();
}
