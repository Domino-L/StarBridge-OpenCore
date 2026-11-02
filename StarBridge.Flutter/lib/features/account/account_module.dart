import 'dart:async';

import 'package:flutter/foundation.dart';

import 'account_models.dart';
import 'account_port.dart';
import 'legacy_profile_migration.dart';
import 'password_recovery.dart';
import 'legacy_password_login.dart';
import 'account_preferences_draft.dart';
import 'account_read_preparation.dart';
import 'account_avatar_read_preparation.dart';
import 'account_restore_display.dart';
import 'account_visible_reads.dart';
import 'account_details_readiness.dart';

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

/// Optional: whether the shell's call sign and photo are final for this
/// session (read, failed, or not applicable). Notified through [projection].
abstract interface class AccountPresentationReadiness {
  bool get presentationSettled;
}

extension AccountPresentationSettled on AccountModule {
  bool get presentationSettled => switch (this) {
    final AccountPresentationReadiness readiness =>
      readiness.presentationSettled,
    _ => true,
  };
}

// Presentation-only, one-shot feedback. Never persisted or used as auth state.
final _loginSuccessGeneration = Expando<int>();

extension AccountLoginFeedback on AccountModule {
  bool takeLoginSuccessFeedback() {
    final pending = _loginSuccessGeneration[this];
    _loginSuccessGeneration[this] = null;
    return pending != null &&
        projection.value.isSignedIn &&
        pending == projection.value.generation;
  }
}

final class _DefaultAccountModule
    implements
        AccountModule,
        AccountReadPreparation,
        AccountPresentationReadiness,
        AccountDetailsReadiness,
        AccountVisibleReads {
  _DefaultAccountModule(this._port) {
    _invalidationSubscription = _port.invalidations.listen(_onInvalidated);
    _restoreDisplay?.addListener(_onRestoreDisplay);
  }

  ValueListenable<AccountProjection?>? get _restoreDisplay =>
      _port is AccountRestoreDisplayPort
      ? (_port as AccountRestoreDisplayPort).restoreDisplay
      : null;

  void _onRestoreDisplay() {
    if (_disposed) return;
    final display = _restoreDisplay?.value;
    if (_projection.value.displayHandoff != null &&
        display?.displayHandoff == null) {
      final current = _projection.value;
      _projection.value = _snapshot == null
          ? const AccountProjection.loading().copyWith(
              generation: current.generation,
              operation: current.operation,
            )
          : current.copyWith(clearDisplayHandoff: true);
    }
    if (!_readInFlight || _snapshot != null) return;
    if (display != null &&
        display.generation == _projection.value.generation &&
        _projection.value.sessionState == AccountSessionState.loading) {
      _projection.value = display;
    } else if (_projection.value.isPreparingDisplay && display == null) {
      _projection.value = const AccountProjection.loading().copyWith(
        generation: _projection.value.generation,
      );
    }
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
  bool _preparationInFlight = false, _readPreparationRetryDue = false;
  int _preparationEpoch = 0;
  // The account page shows the staged details (2026-10-21).
  late final _visibleReads = AccountVisibleReadDriver(
    prepareNext: prepareNextRead,
    inFlight: () => _preparationInFlight,
  );
  @override
  void Function() holdVisibleReads() => _visibleReads.hold();
  bool _avatarInFlight = false, _avatarRetryDue = false;
  int _avatarEpoch = 0, _avatarRetryAttempt = 0;
  Timer? _avatarRecovery;
  AccountAvatarReadResult? _avatarPresentation;
  bool _avatarAttemptFailed = false;

  @override
  bool get presentationSettled {
    final value = _projection.value;
    if (!value.isSignedIn || _avatarPort == null) return true;
    final avatar = _avatarPresentation, snapshot = _snapshot;
    return _avatarAttemptFailed ||
        avatar != null &&
            snapshot != null &&
            avatar.matches(snapshot.route, snapshot.generation);
  }

  @override
  bool get signedInDetailsSettled =>
      _projection.value.isSignedIn &&
      !_projection.value.isBusy &&
      !_preparationInFlight &&
      presentationSettled &&
      !(_preparationPort?.hasPendingReadPreparation ?? false) &&
      !_readPreparationRetryDue;

  AccountAvatarReadPreparationPort? get _avatarPort =>
      _port is AccountAvatarReadPreparationPort &&
          (_port as AccountAvatarReadPreparationPort)
              .supportsAvatarReadPreparation
      ? _port as AccountAvatarReadPreparationPort
      : null;
  AccountReadPreparationPort? get _preparationPort =>
      _port is AccountReadPreparationPort &&
          (_port as AccountReadPreparationPort).supportsStagedReads
      ? _port as AccountReadPreparationPort
      : null;
  int _operationRevision = 0;
  Timer? _profileRecovery;
  int _profileRecoveryAttempt = 0;
  static const _profileBackoff = [2, 5, 10, 30];

  @override
  ValueListenable<AccountProjection> get projection => _projection;

  @override
  bool get supportsPreparedReads => _preparationPort != null;

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
  Future<AccountActionResult> refresh() => _refresh(recovery: false);

  // Warm-up deferral and same-account refreshes cancel only the staged
  // metadata reads. The call sign/photo read is first-glance content (the
  // shell and startup wait for it): cancelling it on every click left the
  // first read failing in 40/40 device samples and the name missing for
  // 27-50 s until the whole warm-up queue drained (2026-10-20).
  @override
  void cancelReadPreparation() {
    // A click must not cancel what the visible account page is reading.
    if (!_visibleReads.held) _cancelReadPreparation();
  }

  void _cancelReadPreparation() {
    ++_preparationEpoch;
    _preparationPort?.cancelReadPreparation();
  }

  void _cancelAvatarRead() {
    ++_avatarEpoch;
    _avatarInFlight = false;
    _avatarPort?.cancelAvatarReadPreparation();
  }

  @override
  Future<bool> prepareNextRead() async {
    _startAvatarRead();
    final port = _preparationPort;
    if (_disposed ||
        port == null ||
        _readInFlight ||
        _projection.value.isBusy) {
      return false;
    }
    if (_preparationInFlight) return true;
    if (!port.hasPendingReadPreparation && !_readPreparationRetryDue) {
      return false;
    }
    _preparationInFlight = true;
    final epoch = _preparationEpoch, revision = _operationRevision;
    final retry = _readPreparationRetryDue;
    _readPreparationRetryDue = false;
    try {
      final result = await port.prepareNextRead(retry: retry);
      if (!_disposed &&
          epoch == _preparationEpoch &&
          revision == _operationRevision &&
          result != null) {
        _finish(revision, result, preserveNotice: true);
      }
    } finally {
      _preparationInFlight = false;
    }
    return true;
  }

  // Admit presentation before the client's phased metadata queue. Native still
  // owns its account/credential serialization; this is not a bypass of that
  // barrier. Merge only presentation into the latest snapshot, never old grants.
  void _startAvatarRead() {
    final port = _avatarPort;
    if (_disposed ||
        port == null ||
        _avatarInFlight ||
        _projection.value.isBusy ||
        !_projection.value.isSignedIn ||
        _projection.value.profile == null &&
            _projection.value.failure != null ||
        _snapshot == null ||
        (_avatarRecovery?.isActive ?? false)) {
      return;
    }
    _avatarInFlight = true;
    final epoch = _avatarEpoch, retry = _avatarRetryDue;
    _avatarRetryDue = false;
    unawaited(() async {
      try {
        final result = await port.prepareAvatarRead(retry: retry);
        // Owner and generation are checked by matches(); a same-account
        // refresh that completed meanwhile must not discard the call sign.
        if (_disposed ||
            epoch != _avatarEpoch ||
            result == null ||
            _snapshot == null ||
            !result.matches(_snapshot!.route, _snapshot!.generation)) {
          return;
        }
        if (result.hasPresentation) {
          _avatarPresentation = result;
          _avatarRetryAttempt = 0;
          _snapshot = _snapshot!.copyWith(
            profile: result.apply(_snapshot!.profile),
          );
          _projection.value = _projection.value.copyWith(
            profile: result.apply(_projection.value.profile),
          );
        } else if (result.retryable &&
            _avatarRetryAttempt < _profileBackoff.length) {
          // A transient failure is not yet settled; the idle work queue
          // admits the retry once the backoff has elapsed.
          _avatarRetryDue = true;
          _avatarRecovery = Timer(
            Duration(seconds: _profileBackoff[_avatarRetryAttempt++]),
            () {
              _avatarRecovery = null;
              if (!_disposed) _projection.value = _projection.value.copyWith();
            },
          );
        } else if (result.retryable) {
          // Retries exhausted: settle so startup is not held by this item.
          _avatarAttemptFailed = true;
          _projection.value = _projection.value.copyWith();
        }
      } on Object {
        /* Optional presentation failure never changes authentication. */
        if (!_disposed && epoch == _avatarEpoch) {
          _avatarAttemptFailed = true;
          _projection.value = _projection.value.copyWith();
        }
      } finally {
        if (epoch == _avatarEpoch) _avatarInFlight = false;
      }
    }());
  }

  Future<AccountActionResult> _refresh({required bool recovery}) async {
    if (_disposed) {
      return const AccountActionResult(AccountActionOutcome.rejected);
    }
    if (_readInFlight) {
      // A completed profile write may request a read while an older read is
      // still pending. Coalesce, rather than lose, that refresh intent.
      _refreshPending = true;
      return const AccountActionResult(AccountActionOutcome.rejected);
    }
    if (_projection.value.isBusy &&
        _projection.value.operation != AccountOperation.refreshing) {
      _refreshPending = true;
      return const AccountActionResult(AccountActionOutcome.rejected);
    }
    if (!recovery) {
      _profileRecoveryAttempt = 0;
      _avatarRetryAttempt = 0;
      _avatarRetryDue = false;
      _avatarRecovery?.cancel();
    }
    final generationBeforeRead = _projection.value.generation;
    final revision = ++_operationRevision;
    _readInFlight = true;
    _setOperation(AccountOperation.refreshing);
    final AccountPortResult result;
    try {
      result = await _port.read();
    } finally {
      _readInFlight = false;
    }
    return _finish(
      revision,
      result,
      transitionFromGeneration: generationBeforeRead,
    );
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
    final generationBeforeCommand = _projection.value.generation;
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
      transitionFromGeneration:
          command is BeginAccountLogin || command is LogoutAccount
          ? generationBeforeCommand
          : null,
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
    int? transitionFromGeneration,
    bool preserveNotice = false,
  }) {
    if (_disposed) return const AccountActionResult(AccountActionOutcome.stale);
    var snapshot = result.snapshot;
    // A read or explicit login/logout may already have confirmed the new Host
    // generation. Accept that result, never a reply from the retired generation.
    final confirmsCurrentTransition =
        transitionFromGeneration != null &&
        result.outcome == AccountActionOutcome.completed &&
        snapshot != null &&
        snapshot.generation > transitionFromGeneration &&
        snapshot.generation == _projection.value.generation;
    if (revision != _operationRevision && !confirmsCurrentTransition) {
      if (!_disposed &&
          _refreshPending &&
          !_readInFlight &&
          !_projection.value.isBusy) {
        _refreshPending = false;
        unawaited(refresh());
      }
      return const AccountActionResult(AccountActionOutcome.stale);
    }
    // A Host invalidation already scheduled the replacement read. The stale
    // reply is an internal handoff, not a failure the user needs to resolve.
    if (_refreshPending && result.failure?.code == 'bridge.stale_generation') {
      _refreshPending = false;
      unawaited(refresh());
      return const AccountActionResult(AccountActionOutcome.stale);
    }
    if (snapshot != null &&
        (_snapshot == null || snapshot.generation >= _snapshot!.generation)) {
      final display = _restoreDisplay?.value;
      final handoff = display?.displayHandoff;
      if (handoff?.matches(snapshot) == true && snapshot.profile == null) {
        snapshot = snapshot.copyWith(
          profile: display!.profile,
          profileFreshness: AccountProfileFreshness.cached,
          cachedAt: display.cachedAt,
        );
      }
      final avatar = _avatarPresentation;
      if (snapshot.sessionState != AccountSessionState.signedIn ||
          snapshot.profile == null &&
              (result.failure != null ||
                  successNotice?.messageKey == 'account.cache.cleared')) {
        _avatarPresentation = null;
        _avatarAttemptFailed = false;
        _cancelAvatarRead();
        _avatarRecovery?.cancel();
      } else if (avatar != null &&
          avatar.matches(snapshot.route, snapshot.generation)) {
        snapshot = snapshot.copyWith(profile: avatar.apply(snapshot.profile));
      }
      _snapshot = snapshot;
      if (snapshot.sessionState != AccountSessionState.signedIn) {
        _loginSuccessGeneration[this] = null;
      } else if (result.outcome == AccountActionOutcome.completed &&
          successNotice?.messageKey == 'account.login.success') {
        _loginSuccessGeneration[this] = snapshot.generation;
      }
      final projection = AccountProjection.fromSnapshot(
        snapshot,
        failure: result.failure,
        notice: result.failure != null
            ? null
            : result.outcome == AccountActionOutcome.completed
            ? successNotice ??
                  (preserveNotice ? _projection.value.notice : null)
            : cancelledNotice ??
                  const AccountNotice(
                    kind: AccountNoticeKind.information,
                    messageKey: 'account.login.cancelled',
                  ),
      );
      _projection.value = projection.copyWith(
        displayHandoff: handoff?.matches(snapshot) == true ? handoff : null,
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
    // The call sign is first-glance content and startup waits for it. Start it
    // as soon as a read lands (build 12: warm-up reached it at 15.8 s), also
    // before a queued same-account refresh: started after that refresh it
    // queued behind the shell's social reads (build 16: 6.05 s → 14.97 s).
    if (!presentationSettled) _startAvatarRead();
    if (_refreshPending) {
      _refreshPending = false;
      unawaited(refresh());
    } else {
      _scheduleProfileRecovery();
      unawaited(_visibleReads.drain());
    }
    return AccountActionResult(result.outcome, failure: result.failure);
  }

  void _setOperation(AccountOperation operation) {
    _cancelReadPreparation();
    // Sign-in/out and similar may change the account; a refresh does not.
    if (operation != AccountOperation.refreshing) _cancelAvatarRead();
    _readPreparationRetryDue = false;
    _profileRecovery?.cancel();
    _profileRecovery = null;
    _projection.value = _projection.value.copyWith(
      operation: operation,
      clearFailure: operation != AccountOperation.refreshing,
      clearNotice: true,
    );
  }

  void _scheduleProfileRecovery() {
    _profileRecovery?.cancel();
    _profileRecovery = null;
    final current = _projection.value;
    final preparation = _preparationPort;
    if (preparation?.hasPendingReadPreparation == true) return;
    if (_disposed ||
        !current.isSignedIn ||
        !(preparation != null
            ? preparation.shouldRetryReadPreparation
            : current.profileFreshness == AccountProfileFreshness.cached)) {
      _profileRecoveryAttempt = 0;
      return;
    }
    if (current.isBusy || _profileRecoveryAttempt >= _profileBackoff.length) {
      return;
    }
    final revision = _operationRevision;
    final delay = _profileBackoff[_profileRecoveryAttempt++];
    _profileRecovery = Timer(Duration(seconds: delay), () {
      _profileRecovery = null;
      if (!_disposed &&
          revision == _operationRevision &&
          !_projection.value.isBusy) {
        if (preparation != null) {
          // Signal the idle owner; a backoff timer never starts private IO.
          _readPreparationRetryDue = true;
          _projection.value = _projection.value.copyWith();
        } else {
          unawaited(_refresh(recovery: true));
        }
      }
    });
  }

  void _onInvalidated(AccountInvalidation invalidation) {
    if (_disposed || invalidation.generation < _projection.value.generation) {
      return;
    }
    _avatarPresentation = null;
    _avatarAttemptFailed = false;
    _avatarRetryAttempt = 0;
    _avatarRetryDue = false;
    _avatarRecovery?.cancel();
    _cancelReadPreparation();
    _cancelAvatarRead();
    final wasBusy = _projection.value.isBusy || _readInFlight;
    if (invalidation.generation > _projection.value.generation) {
      ++_operationRevision;
      _snapshot = null;
      _profileRecovery?.cancel();
      _profileRecovery = null;
      final display = _restoreDisplay?.value;
      _projection.value =
          display?.hasDisplayHandoff == true &&
              display!.generation == invalidation.generation
          ? display.copyWith(operation: AccountOperation.none)
          : const AccountProjection.loading().copyWith(
              generation: invalidation.generation,
              operation: AccountOperation.none,
            );
    }
    if (wasBusy) {
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
    _restoreDisplay?.removeListener(_onRestoreDisplay);
    _cancelReadPreparation();
    _cancelAvatarRead();
    _avatarRecovery?.cancel();
    _profileRecovery?.cancel();
    unawaited(_invalidationSubscription.cancel());
    unawaited(_port.close());
    preferencesDraft.dispose();
    _projection.dispose();
  }
}
