import 'package:flutter/foundation.dart';

/// The installed SCM account's own display data, read after setup finished.
/// The avatar is the RSI avatar (read-only here); only the nickname changes.
@immutable
final class OnboardingProfileSnapshot {
  const OnboardingProfileSnapshot({
    required this.callSign,
    this.avatarImageData,
    this.canRename = false,
    this.canOpenRsi = false,
  });
  final String callSign;
  final String? avatarImageData;
  final bool canRename, canOpenRsi;
}

/// A rename the Host did not confirm. [key] is an onboarding copy key.
final class OnboardingProfileSaveException implements Exception {
  const OnboardingProfileSaveException(this.key, {this.conflict = false});
  final String key;

  /// The name changed elsewhere since it was read; reread before retrying.
  final bool conflict;
}

abstract interface class OnboardingProfilePort {
  Stream<void> get invalidations;

  /// Null while no SCM account is installed (local route, legacy, or still
  /// switching). Never a placeholder account.
  Future<OnboardingProfileSnapshot?> read();

  /// Returns the confirmed nickname, or throws [OnboardingProfileSaveException].
  Future<String> saveCallSign(String expected, String next);

  Future<void> openRsiProfile();
}

/// Same rule as the Host: 1–32 characters, no surrounding space or control
/// characters.
bool validOnboardingCallSign(String value) =>
    value.isNotEmpty &&
    value.length <= 32 &&
    value == value.trim() &&
    !value.runes.any((r) => r < 0x20 || (r >= 0x7F && r < 0xA0));
