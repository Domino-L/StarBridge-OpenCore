import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/app/startup/startup_session.dart';
import 'package:starbridge_flutter/app/startup/startup_motion_spec.dart';

void main() {
  test('ready before presentation skips all motion', () {
    final session = StartupSession();
    addTearDown(session.dispose);
    session.readingPreferences();
    session.resolveAccount(_signedOut);
    expect(session.complete, isTrue);
  });

  test('presented startup waits for real ready then completes once', () {
    final session = StartupSession(random: Random(8));
    addTearDown(session.dispose);
    final spec = session.spec;
    session.markPresented();
    session.readingPreferences();
    expect(session.value, StartupPhase.preferences);
    session.resolveAccount(_signedOut);
    expect(session.value, StartupPhase.ready);
    session.enter();
    session.hostUnavailable();
    session.connecting(manual: true);
    session.readingPreferences();
    expect(session.complete, isTrue);
    expect(identical(session.spec, spec), isTrue);
  });

  test('background retries retain failure until meaningful progress', () {
    final session = StartupSession();
    addTearDown(session.dispose);
    session.hostUnavailable();
    session.connecting();
    expect(session.value, StartupPhase.hostUnavailable);
    session.connecting(manual: true);
    expect(session.value, StartupPhase.connecting);
    session.readingPreferences();
    session.preferencesUnavailable();
    expect(session.value, StartupPhase.preferencesUnavailable);
  });

  test('manual entry is terminal even while connection remains pending', () {
    final session = StartupSession();
    session.enter();
    session.resolveAccount(_signedOut);
    expect(session.complete, isTrue);
    session.dispose();
    expect(() => session.hostUnavailable(), returnsNormally);
  });

  test('all five approved directions can be chosen with bounded handoff', () {
    final directions = <StartupMotionDirection>{};
    final random = Random(34);
    for (var i = 0; i < 200; i++) {
      final spec = StartupMotionSpec.choose(random);
      directions.add(spec.direction);
      expect(spec.handoffDuration.inMilliseconds, lessThanOrEqualTo(190));
    }
    expect(directions, StartupMotionDirection.values.toSet());
  });

  test(
    'first account check cannot be replaced by a timer or missing profile',
    () {
      final session = StartupSession()..markPresented();
      addTearDown(session.dispose);
      session.resolveAccount(const AccountProjection.loading());
      expect(session.value, StartupPhase.account);
      expect(session.accountStatus, StartupAccountStatus.loading);
      session.resolveAccount(
        const AccountProjection.loading().copyWith(
          operation: AccountOperation.none,
        ),
      );
      expect(session.value, StartupPhase.account);
    },
  );

  for (final state in [
    AccountSessionState.signedIn,
    AccountSessionState.signedOut,
    AccountSessionState.reauthorizationRequired,
  ]) {
    test('a resolved $state can enter without interactive login', () {
      final session = StartupSession()..markPresented();
      addTearDown(session.dispose);
      session.resolveAccount(_signedOut.copyWith(sessionState: state));
      expect(session.value, StartupPhase.ready);
      expect(session.accountStatus.name, state.name);
    });
  }

  test('unavailable account stays actionable; retry ignores old failure while busy', () {
    final session = StartupSession()..markPresented();
    addTearDown(session.dispose);
    final unavailable = _signedOut.copyWith(
      sessionState: AccountSessionState.credentialTemporarilyUnavailable,
    );
    session.resolveAccount(unavailable);
    expect(session.value, StartupPhase.accountUnavailable);
    expect(session.value.failed, isTrue);
    session.resolveAccount(
      unavailable.copyWith(operation: AccountOperation.refreshing),
    );
    expect(session.value, StartupPhase.account);
    session.enter();
    session.resolveAccount(_signedOut);
    expect(session.complete, isTrue);
  });

  test('legacy account with unavailable Relay credentials is not shown as signed in', () {
    final session = StartupSession()..markPresented();
    addTearDown(session.dispose);
    session.resolveAccount(
      _signedOut.copyWith(sessionState: AccountSessionState.legacyUnavailable),
    );
    expect(session.value, StartupPhase.accountUnavailable);
    expect(session.accountStatus, StartupAccountStatus.failed);
  });
}

final _signedOut = AccountProjection.fromSnapshot(
  const AccountHostSnapshot.signedOut(generation: 0),
);
