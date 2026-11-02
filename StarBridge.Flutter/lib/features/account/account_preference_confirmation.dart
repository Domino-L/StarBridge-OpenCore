import '../../platform/bridge/bridge_envelope.dart';
import 'account_models.dart';
import 'account_payload_decoder.dart';

/// Consumes the confirmed write only; reference options are prepared separately.
({AccountHostSnapshot snapshot, DateTime observedAtUtc})
decodeAccountPreferenceConfirmation(
  AccountHostSnapshot current,
  Map<String, Object?> payload,
) {
  final data = AccountPayloadDecoder.profile(
    payload,
    allowDirectoryOmission: true,
  );
  if (data.freshness != AccountProfileFreshness.live) {
    throw const BridgeFormatException('Preference confirmation must be live.');
  }
  return (
    snapshot: current.copyWith(
      profile: data.profile.copyWith(
        displayName: current.profile?.displayName,
        avatarImageData: current.profile?.avatarImageData,
      ),
      profileFreshness: data.freshness,
      cachedAt: data.cachedAt,
      clearCachedAt: data.cachedAt == null,
      localeOptions: data.localeOptions,
      timeZoneOptions: data.directoryIncluded
          ? data.timeZoneOptions
          : current.timeZoneOptions,
      supportsPreferenceWrite:
          data.supportsPreferenceWrite &&
          (data.directoryIncluded || current.supportsPreferenceWrite),
      supportsCacheClear: data.supportsCacheClear,
    ),
    observedAtUtc: data.observedAt ?? DateTime.now().toUtc(),
  );
}
