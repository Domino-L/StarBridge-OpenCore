import 'dart:async';

import 'package:flutter/foundation.dart';

import 'account_models.dart';
import 'account_port.dart';
import 'legacy_profile_migration.dart';
import 'password_recovery.dart';
import 'legacy_password_login.dart';
import 'account_preferences_draft.dart';

abstract interface class AccountModule {
  AccountPreferencesDraft get preferencesDraft;
  LegacyPasswordLoginPort? get legacyPasswordLogin;
  PasswordRecoveryPort? get passwordRecovery;
  LegacyProfileMigrationPort? get legacyMigration;
  ValueListenable<AccountProjection> get projection;

  Future<AccountActionResult> initialize();
  Future<AccountActionResult> refresh();
  Future<AccountActionResult> beginLogin();
  Future<AccountActionResult> cancelLogin();
  Future<AccountActionResult> logout();
  Future<AccountActionResult> linkLegacyAccount({
    String? accountName,
    String? password,
  });
  Future<AccountActionResult> createCompatibilityIdentity();
  Future<AccountActionResult> cancelCompatibilityOperation();
  Future<AccountActionResult> savePreferences({
    required String? locale,
    required String? timeZone,
  });
  Future<AccountActionResult> clearLocalCache();
  void dispose();
}

AccountModule createAccountModule(AccountPort port) =>
    _DefaultAccountModule(port);

final class _DefaultAccountModule implements AccountModule {
  _DefaultAccountModule(this._port) {
    _invalidationSubscription = _port.invalidations.listen(_onInvalidated);
  }

  final AccountPort _port;
  @override
  late final AccountPreferencesDraft preferencesDraft = AccountPreferencesDraft(
    _projection,
  );
  @override
  LegacyPasswordLoginPort? get legacyPasswordLogin =>
      _port is LegacyPasswordLoginPort &&
          (_port as LegacyPasswordLoginPort).supportsLegacyPasswordLogin
      ? _port as LegacyPasswordLoginPort
      : null;
  @override
  PasswordRecoveryPort? get passwordRecovery =>
      _port is PasswordRecoveryPort &&
          (_port as PasswordRecoveryPort).supportsPasswordRecovery
      ? _port as PasswordRecoveryPort
      : null;
  @override
  LegacyProfileMigrationPort? get legacyMigration =>
      _port is LegacyProfileMigrationPort
      ? _port as LegacyProfileMigrationPort
      : null;
  final ValueNotifier<AccountProjection> _projection = ValueNotifier(
    const AccountProjection.loading(),
  );
  late final StreamSubscription<AccountInvalidation> _invalidationSubscription;

  AccountHostSnapshot? _snapshot;
  bool _initialized = false;
  bool _disposed = false;
  bool _refreshPending = false;
  bool _readInFlight = false;
  int _operationRevision = 0;

  @override
  ValueListenable<AccountProjection> get projection => _projection;

  @override
  Future<AccountActionResult> initialize() {
    if (_initialized) {
      return Future.value(
        const AccountActionResult(AccountActionOutcome.completed),
      );
    }
    _initialized = true;
    return refresh();
  }

  @override
  Future<AccountActionResult> refresh() async {
    if (_disposed || _readInFlight) {
      return const AccountActionResult(AccountActionOutcome.rejected);
    }
    if (_projection.value.isBusy &&
        _projection.value.operation != AccountOperation.refreshing) {
      _refreshPending = true;
      return const AccountActionResult(AccountActionOutcome.rejected);
    }
    final revision = ++_operationRevision;
    _readInFlight = true;
    _setOperation(AccountOperation.refreshing);
    final AccountPortResult result;
    try {
      result = await _port.read();
    } finally {
      _readInFlight = false;
    }
    return _finish(revision, result);
  }

  @override
  Future<AccountActionResult> beginLogin() {
    if (!_projection.value.canLogin) {
      return Future.value(
        const AccountActionResult(AccountActionOutcome.rejected),
      );
    }
    return _runCommand(
      const BeginAccountLogin(),
      AccountOperation.signingIn,
      successMessageKey: 'account.login.success',
    );
  }

  @override
  Future<AccountActionResult> cancelLogin() async {
    if (_projection.value.operation != AccountOperation.signingIn) {
      return const AccountActionResult(AccountActionOutcome.rejected);
    }
    final revision = ++_operationRevision;
    _setOperation(AccountOperation.cancellingLogin);
    final result = await _port.execute(const CancelAccountLogin());
    return _finish(
      revision,
      result,
      successNotice: const AccountNotice(
        kind: AccountNoticeKind.information,
        messageKey: 'account.login.cancelled',
      ),
    );
  }

  @override
  Future<AccountActionResult> logout() {
    if (!_projection.value.canLogout) {
      return Future.value(
        const AccountActionResult(AccountActionOutcome.rejected),
      );
    }
    return _runCommand(
      const LogoutAccount(),
      AccountOperation.signingOut,
      successMessageKey: 'account.logout.success',
    );
  }

  @override
  Future<AccountActionResult> linkLegacyAccount({
    String? accountName,
    String? password,
  }) {
    if (!_projection.value.canLinkLegacyAccount) {
      return Future.value(
        const AccountActionResult(AccountActionOutcome.rejected),
      );
    }
    final hasManualCredential =
        accountName?.trim().isNotEmpty == true && password?.isNotEmpty == true;
    final canUseStoredCredential =
        _projection.value.compatibility.storedLegacyCredentialAvailable;
    if (!hasManualCredential && !canUseStoredCredential) {
      return Future.value(
        const AccountActionResult(AccountActionOutcome.rejected),
      );
    }
    return _runCommand(
      LinkLegacyAccount(
        credential: hasManualCredential
            ? LegacyAccountCredential(
                accountName: accountName!.trim(),
                password: password!,
              )
            : null,
      ),
      AccountOperation.linkingLegacyAccount,
      successMessageKey: 'account.compatibility.linked',
    );
  }

  @override
  Future<AccountActionResult> createCompatibilityIdentity() {
    if (!_projection.value.canCreateCompatibilityIdentity) {
      return Future.value(
        const AccountActionResult(AccountActionOutcome.rejected),
      );
    }
    return _runCommand(
      const CreateCompatibilityIdentity(),
      AccountOperation.creatingCompatibilityIdentity,
      successMessageKey: 'account.compatibility.created',
    );
  }

  @override
  Future<AccountActionResult> cancelCompatibilityOperation() async {
    if (!_projection.value.canCancelCompatibilityOperation) {
      return const AccountActionResult(AccountActionOutcome.rejected);
    }
    final revision = ++_operationRevision;
    _setOperation(AccountOperation.cancellingCompatibilityOperation);
    final result = await _port.execute(const CancelCompatibilityOperation());
    return _finish(
      revision,
      result,
      successNotice: const AccountNotice(
        kind: AccountNoticeKind.information,
        messageKey: 'account.compatibility.cancelled',
      ),
      cancelledNotice: const AccountNotice(
        kind: AccountNoticeKind.information,
        messageKey: 'account.compatibility.cancelled',
      ),
    );
  }

  @override
  Future<AccountActionResult> savePreferences({
    required String? locale,
    required String? timeZone,
  }) {
    final current = _snapshot?.profile;
    if (!_projection.value.canEditPreferences || current == null) {
      return Future.value(
        const AccountActionResult(AccountActionOutcome.rejected),
      );
    }
    final patch = AccountPreferencePatch(
      localeSpecified: locale != current.locale,
      locale: locale,
      timeZoneSpecified: timeZone != current.timeZone,
      timeZone: timeZone,
    );
    if (patch.isEmpty) {
      _projection.value = _projection.value.copyWith(
        operation: AccountOperation.none,
        clearFailure: true,
        notice: const AccountNotice(
          kind: AccountNoticeKind.information,
          messageKey: 'account.preferences.noChanges',
        ),
      );
      return Future.value(
        const AccountActionResult(AccountActionOutcome.completed),
      );
    }
    return _runCommand(
      SaveAccountPreferences(patch: patch),
      AccountOperation.savingPreferences,
      successMessageKey: 'account.preferences.saved',
    );
  }

  @override
  Future<AccountActionResult> clearLocalCache() {
    if (!_projection.value.canClearProfileCache) {
      return Future.value(
        const AccountActionResult(AccountActionOutcome.rejected),
      );
    }
    return _runCommand(
      const ClearAccountProfileCache(),
      AccountOperation.clearingCache,
      successMessageKey: 'account.cache.cleared',
    );
  }

  Future<AccountActionResult> _runCommand(
    AccountPortCommand command,
    AccountOperation operation, {
    required String successMessageKey,
  }) async {
    if (_disposed || _projection.value.isBusy) {
      return const AccountActionResult(AccountActionOutcome.rejected);
    }
    final revision = ++_operationRevision;
    final wasLegacy = _projection.value.isLegacyAccount;
    _setOperation(operation);
    var result = await _port.execute(command);
    if (wasLegacy &&
        command is BeginAccountLogin &&
        result.failure != null &&
        result.outcome == AccountActionOutcome.failed) {
      result = const AccountPortResult.failed(
        AccountFailure(
          code: 'account.optional_scm_failed',
          messageKey: 'account.legacySession.scmFailed',
          retryable: false,
        ),
      );
    }
    return _finish(
      revision,
      result,
      successNotice: AccountNotice(
        kind: AccountNoticeKind.success,
        messageKey: successMessageKey,
      ),
      cancelledNotice: command is SaveAccountPreferences
          ? const AccountNotice(
              kind: AccountNoticeKind.information,
              messageKey: 'account.preferences.cancelled',
            )
          : null,
    );
  }

  AccountActionResult _finish(
    int revision,
    AccountPortResult result, {
    AccountNotice? successNotice,
    AccountNotice? cancelledNotice,
  }) {
    if (_disposed || revision != _operationRevision) {
      return const AccountActionResult(AccountActionOutcome.stale);
    }
    // A Host invalidation already scheduled the replacement read. The stale
    // reply is an internal handoff, not a failure the user needs to resolve.
    if (_refreshPending && result.failure?.code == 'bridge.stale_generation') {
      _refreshPending = false;
      unawaited(refresh());
      return const AccountActionResult(AccountActionOutcome.stale);
    }
    final snapshot = result.snapshot;
    if (snapshot != null &&
        (_snapshot == null || snapshot.generation >= _snapshot!.generation)) {
      _snapshot = snapshot;
      _projection.value = AccountProjection.fromSnapshot(
        snapshot,
        failure: result.failure,
        notice: result.outcome == AccountActionOutcome.completed
            ? successNotice
            : cancelledNotice ??
                  const AccountNotice(
                    kind: AccountNoticeKind.information,
                    messageKey: 'account.login.cancelled',
                  ),
      );
    } else if (result.failure case final failure?) {
      _projection.value = _projection.value.copyWith(
        operation: AccountOperation.none,
        failure: failure,
        clearNotice: true,
      );
    } else {
      _projection.value = _projection.value.copyWith(
        operation: AccountOperation.none,
        clearFailure: true,
      );
    }
    if (_refreshPending) {
      _refreshPending = false;
      unawaited(refresh());
    }
    return AccountActionResult(result.outcome, failure: result.failure);
  }

  void _setOperation(AccountOperation operation) {
    _projection.value = _projection.value.copyWith(
      operation: operation,
      clearFailure: operation != AccountOperation.refreshing,
      clearNotice: true,
    );
  }

  void _onInvalidated(AccountInvalidation invalidation) {
    if (_disposed ||
        (_snapshot != null &&
            invalidation.generation < _snapshot!.generation)) {
      return;
    }
    if (_projection.value.isBusy) {
      _refreshPending = true;
      return;
    }
    unawaited(refresh());
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_invalidationSubscription.cancel());
    unawaited(_port.close());
    preferencesDraft.dispose();
    _projection.dispose();
  }
}
