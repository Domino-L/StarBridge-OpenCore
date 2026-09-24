import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import 'startup_motion_spec.dart';

enum StartupPhase {
  connecting,
  preferences,
  account,
  ready,
  hostUnavailable,
  preferencesUnavailable,
  accountUnavailable,
  complete;

  bool get failed =>
      this == hostUnavailable ||
      this == preferencesUnavailable ||
      this == accountUnavailable;
}

enum StartupAccountStatus {
  waiting,
  loading,
  signedIn,
  signedOut,
  reauthorizationRequired,
  failed,
}

/// Owned by RuntimeHost, above composition replacement and its keyed App.
/// Only observed initialization outcomes can advance this session to ready.
class StartupSession extends ValueNotifier<StartupPhase> {
  StartupSession({Random? random})
    : spec = StartupMotionSpec.choose(random),
      super(StartupPhase.connecting);

  final StartupMotionSpec spec;
  bool _presented = false;
  bool _disposed = false;
  StartupAccountStatus _accountStatus = StartupAccountStatus.waiting;
  StartupAccountStatus get accountStatus => _accountStatus;
  bool get complete => value == StartupPhase.complete;

  void markPresented() => _presented = true;

  void connecting({bool manual = false}) {
    // A background retry must not flicker the failure message or its actions.
    if (!value.failed || manual) _set(StartupPhase.connecting);
  }

  void readingPreferences() => _set(StartupPhase.preferences);
  void hostUnavailable() => _set(StartupPhase.hostUnavailable);
  void preferencesUnavailable() => _set(StartupPhase.preferencesUnavailable);
  void readingAccount() {
    if (_disposed || complete) return;
    _accountStatus = StartupAccountStatus.loading;
    _set(StartupPhase.account);
  }

  /// Consume the existing account read, never start a second authentication flow.
  void resolveAccount(AccountProjection account) {
    if (_disposed || complete) return;
    if (account.isBusy) {
      readingAccount();
      return;
    }
    if (account.failure != null ||
        account.sessionState ==
            AccountSessionState.credentialTemporarilyUnavailable ||
        account.sessionState == AccountSessionState.legacyUnavailable) {
      _accountStatus = StartupAccountStatus.failed;
      _set(StartupPhase.accountUnavailable);
      return;
    }
    _accountStatus = switch (account.sessionState) {
      AccountSessionState.signedIn => StartupAccountStatus.signedIn,
      AccountSessionState.legacySignedIn => StartupAccountStatus.signedIn,
      AccountSessionState.legacyUnavailable => StartupAccountStatus.signedIn,
      AccountSessionState.signedOut => StartupAccountStatus.signedOut,
      AccountSessionState.reauthorizationRequired =>
        StartupAccountStatus.reauthorizationRequired,
      _ => StartupAccountStatus.loading,
    };
    if (_accountStatus == StartupAccountStatus.loading) {
      _set(StartupPhase.account);
    } else {
      _set(_presented ? StartupPhase.ready : StartupPhase.complete);
    }
  }

  void enter() => _set(StartupPhase.complete);

  void _set(StartupPhase next) {
    if (!_disposed && !complete && value != next) value = next;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
