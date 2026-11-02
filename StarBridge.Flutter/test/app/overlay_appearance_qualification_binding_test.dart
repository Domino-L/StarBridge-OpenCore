import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/overlay_appearance_qualification_binding.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';

import '../features/onboarding/connection_mode_test.dart' show modeFact;

void main() {
  const signedIn = AccountSessionState.signedIn;
  test('saved modes that stop entitlement reads are unknown', () {
    for (final state in ['offline', 'signInRequired', 'recoveryRequired']) {
      expect(
        overlayAppearanceQualificationUnknown(signedIn, modeFact(state)),
        true,
        reason: state,
      );
    }
    expect(
      overlayAppearanceQualificationUnknown(signedIn, modeFact('online')),
      false,
    );
    expect(overlayAppearanceQualificationUnknown(signedIn, null), false);
  });
  test('only a temporary account failure is unknown', () {
    for (final (session, expected) in [
      (AccountSessionState.credentialTemporarilyUnavailable, true),
      (AccountSessionState.legacyUnavailable, true),
      (AccountSessionState.signedIn, false),
      (AccountSessionState.signedOut, false),
      (AccountSessionState.reauthorizationRequired, false),
    ]) {
      expect(
        overlayAppearanceQualificationUnknown(session, modeFact('online')),
        expected,
        reason: session.name,
      );
    }
  });
}
