import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../features/onboarding/connection_mode_port.dart';
import 'startup_motion_spec.dart';
import '../diagnostics/loading_diagnostics.dart';
import '../../shared/diagnostics/loading_metrics.dart';

enum StartupPhase {
  connecting,
  preferences,
  account,

  /// Signed in; the shell is built offstage and its first-glance items
  /// (call sign, joined organizations, presence, sharing) are still loading.
  content,
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
  onlineRecoveryRequired,
  offline,
  local,
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
  int? _readyGeneration;
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
  void resolvePreparation({
    required bool preferencesConfirmed,
    required AccountProjection account,
    ConnectionModeControl? connectionMode,
    bool firstContentSettled = true,
  }) {
    if (!preferencesConfirmed) {
      preferencesUnavailable();
      return;
    }
    resolveAccount(
      account,
      connectionMode: connectionMode,
      firstContentSettled: firstContentSettled,
    );
  }

  void readingAccount() {
    if (_disposed || complete) return;
    _accountStatus = StartupAccountStatus.loading;
    _set(StartupPhase.account);
  }

  /// Consume existing observations, never start another authentication flow.
  void resolveAccount(
    AccountProjection account, {
    ConnectionModeControl? connectionMode,
    bool firstContentSettled = true,
  }) {
    if (_disposed || complete) return;
    if (connectionMode != null && !connectionMode.allowsOnlineTraffic) {
      final mode = connectionMode.snapshot.state;
      final expectedPause =
          account.failure?.code == 'account.local_mode' ||
          account.failure == null &&
              account.sessionState !=
                  AccountSessionState.credentialTemporarilyUnavailable &&
              account.sessionState != AccountSessionState.legacyUnavailable;
      if (!connectionMode.failed &&
          connectionMode.snapshot.needsOnlineRecovery &&
          account.failure?.code == 'account.local_mode') {
        _accountStatus = StartupAccountStatus.onlineRecoveryRequired;
        _set(StartupPhase.accountUnavailable);
        return;
      }
      if (!connectionMode.failed &&
          expectedPause &&
          (mode == ConnectionModeState.offline ||
              mode == ConnectionModeState.local)) {
        // This confirms local startup, not authentication or online authority.
        _accountStatus = mode == ConnectionModeState.offline
            ? StartupAccountStatus.offline
            : StartupAccountStatus.local;
        _set(_presented ? StartupPhase.ready : StartupPhase.complete);
        return;
      }
      if (!connectionMode.failed &&
          const {
            ConnectionModeState.unsupported,
            ConnectionModeState.unavailable,
            ConnectionModeState.switching,
          }.contains(mode)) {
        readingAccount();
        return;
      }
      if (connectionMode.failed ||
          mode == ConnectionModeState.recoveryRequired) {
        _accountStatus = StartupAccountStatus.failed;
        _set(StartupPhase.accountUnavailable);
        return;
      }
    }
    LoadingMetrics.current?.accountState(
      generation: account.generation,
      busy: account.isBusy,
      refreshing: account.operation == AccountOperation.refreshing,
      resolved:
          account.sessionState != AccountSessionState.loading &&
          account.sessionState !=
              AccountSessionState.credentialTemporarilyUnavailable &&
          account.sessionState != AccountSessionState.legacyUnavailable,
      failed:
          account.failure != null ||
          account.sessionState ==
              AccountSessionState.credentialTemporarilyUnavailable ||
          account.sessionState == AccountSessionState.legacyUnavailable,
      cached: account.profileFreshness == AccountProfileFreshness.cached,
      scm: account.sessionState == AccountSessionState.signedIn,
      legacy: account.sessionState == AccountSessionState.legacySignedIn,
    );
    if (account.isBusy) {
      // A refresh queued behind the read that already confirmed this sign-in
      // (same generation) is background work; it must not hide the shell
      // again. Sign-in/out and other commands still wait, and any failure the
      // refresh later reports is handled below on its next projection.
      if ((value == StartupPhase.ready || value == StartupPhase.content) &&
          account.operation == AccountOperation.refreshing &&
          account.failure == null &&
          account.generation == _readyGeneration &&
          (account.sessionState == AccountSessionState.signedIn ||
              account.sessionState == AccountSessionState.legacySignedIn)) {
        return;
      }
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
    } else if (_accountStatus == StartupAccountStatus.signedIn &&
        !firstContentSettled) {
      // Enter only once what the user sees at a glance is real (user
      // decision 2026-10-20); the binding bounds this wait.
      _readyGeneration = account.generation;
      _set(StartupPhase.content);
    } else {
      _readyGeneration = account.generation;
      _set(_presented ? StartupPhase.ready : StartupPhase.complete);
    }
  }

  void enter() => _set(StartupPhase.complete);

  void _set(StartupPhase next) {
    if (!_disposed && !complete && value != next) {
      LoadingDiagnostics.stage(next.name);
      value = next;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
