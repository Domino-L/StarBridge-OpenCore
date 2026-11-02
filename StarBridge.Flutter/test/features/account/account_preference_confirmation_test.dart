import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_payload_decoder.dart';
import 'package:starbridge_flutter/features/account/account_preference_confirmation.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

Map<String, Object?> payload({
  Object? included = false,
  String source = 'live',
  List<Object?> zones = const [],
}) => {
  'schemaVersion': 1,
  'profile': {'locale': 'en-US', 'timeZone': 'UTC'},
  'source': source,
  'cachedAtUtc': source == 'cache' ? '2026-01-01T00:00:00Z' : null,
  'observedAtUtc': '2026-01-01T00:00:00Z',
  'preferencesPolicy': {
    'directoryIncluded': included,
    'locales': ['en-US'],
    'timeZones': zones,
    'availableActions': ['profile.patchPreferences'],
  },
};

void main() {
  test('directory-free receipt cannot create missing edit preparation', () {
    const current = AccountHostSnapshot(
      generation: 7,
      sessionState: AccountSessionState.signedIn,
      profileFreshness: AccountProfileFreshness.live,
      identity: AccountIdentityProjection.unavailable(),
      compatibility: AccountCompatibilityProjection.unavailable(),
      localeOptions: [],
      timeZoneOptions: [],
    );
    final confirmed = decodeAccountPreferenceConfirmation(current, payload());
    expect(confirmed.snapshot.supportsPreferenceWrite, isFalse);
    expect(confirmed.snapshot.timeZoneOptions, isEmpty);
    expect(confirmed.snapshot.profile?.locale, 'en-US');
  });
  test('omitted directory is accepted only at the live confirmation seam', () {
    expect(
      () => AccountPayloadDecoder.profile(payload()),
      throwsA(isA<BridgeFormatException>()),
    );
    expect(
      AccountPayloadDecoder.profile(
        payload(),
        allowDirectoryOmission: true,
      ).directoryIncluded,
      isFalse,
    );
  });
  for (final value in [null, 'false', 0, <Object?>[]]) {
    test('directory inclusion rejects malformed value $value', () {
      expect(
        () => AccountPayloadDecoder.profile(
          payload(included: value),
          allowDirectoryOmission: true,
        ),
        throwsA(isA<BridgeFormatException>()),
      );
    });
  }
  test(
    'cached confirmation or contradictory directory cannot omit options',
    () {
      for (final input in [
        payload(source: 'cache'),
        payload(
          zones: [
            {'value': 'UTC', 'label': 'UTC', 'offset': 'UTC+00:00'},
          ],
        ),
      ]) {
        expect(
          () => AccountPayloadDecoder.profile(
            input,
            allowDirectoryOmission: true,
          ),
          throwsA(isA<BridgeFormatException>()),
        );
      }
    },
  );
  test(
    'old Host profile without inclusion flag keeps full response semantics',
    () {
      final input = payload(included: true);
      (input['preferencesPolicy']! as Map).remove('directoryIncluded');
      expect(AccountPayloadDecoder.profile(input).directoryIncluded, isTrue);
    },
  );
}
