import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_payload_decoder.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

const current = '1234567890abcdef1234567890abcdef';
const previous = 'abcdef1234567890abcdef1234567890';
BridgeEnvelope root(Map<String, Object?> display) => BridgeEnvelope(
  protocolVersion: 1,
  messageType: 'response',
  name: 'account.getCurrent',
  correlationId: 'continuity',
  sessionGeneration: 7,
  status: 'ok',
  payload: {'retainedDisplay': display},
);
Map<String, Object?> display() => {
  'displayName': 'Saved pilot',
  'cachedAtUtc': '2026-10-14T12:00:00Z',
  'readId': current,
};

void main() {
  test('exact predecessor is a presentation field with no account context', () {
    final retained = AccountPayloadDecoder.retainedDisplay(
      root({...display(), 'previousReadId': previous}),
      AccountSessionState.credentialTemporarilyUnavailable,
    )!;
    expect(retained.readId, current);
    expect(retained.previousReadId, previous);
    final snapshot = AccountHostSnapshot(
      generation: 7,
      sessionState: AccountSessionState.credentialTemporarilyUnavailable,
      profileFreshness: AccountProfileFreshness.cached,
      profile: retained.profile,
      cachedAt: retained.cachedAt,
      retainedReadId: current,
      retainedPreviousReadId: previous,
      identity: const AccountIdentityProjection.unavailable(),
      compatibility: const AccountCompatibilityProjection.unavailable(),
      localeOptions: const [],
      timeZoneOptions: const [],
    );
    final projection = AccountProjection.fromSnapshot(snapshot.copyWith());
    expect(
      projection
          .copyWith(operation: AccountOperation.refreshing)
          .retainedPreviousReadId,
      previous,
    );
    expect(
      projection.copyWith(clearProfile: true).retainedPreviousReadId,
      isNull,
    );
    expect(
      projection.copyWith(clearCachedAt: true).retainedPreviousReadId,
      isNull,
    );
    expect(projection.copyWith(generation: 8).retainedPreviousReadId, isNull);
    expect(
      projection
          .copyWith(sessionState: AccountSessionState.signedOut)
          .retainedPreviousReadId,
      isNull,
    );
    expect(projection.canEditPreferences, isFalse);
  });
  test('older Host without proof remains readable without continuity', () {
    expect(
      AccountPayloadDecoder.retainedDisplay(
        root(display()),
        AccountSessionState.credentialTemporarilyUnavailable,
      )!.previousReadId,
      isNull,
    );
  });
  for (final value in <Object?>[null, 1, true, '', 'A' * 32, current]) {
    test('invalid predecessor is rejected: $value', () {
      expect(
        () => AccountPayloadDecoder.retainedDisplay(
          root({...display(), 'previousReadId': value}),
          AccountSessionState.credentialTemporarilyUnavailable,
        ),
        throwsA(isA<BridgeFormatException>()),
      );
    });
  }
  test('proof without its new descriptor is rejected', () {
    final missing = display()..remove('readId');
    expect(
      () => AccountPayloadDecoder.retainedDisplay(
        root({...missing, 'previousReadId': previous}),
        AccountSessionState.credentialTemporarilyUnavailable,
      ),
      throwsA(isA<BridgeFormatException>()),
    );
  });
}
