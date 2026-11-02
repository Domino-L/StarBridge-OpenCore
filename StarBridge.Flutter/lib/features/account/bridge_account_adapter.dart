import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'account_models.dart';
import 'account_port.dart';
import 'account_payload_decoder.dart';
import 'account_preference_confirmation.dart';
import 'legacy_profile_migration.dart';
import 'password_recovery.dart';
import 'legacy_password_login.dart';
import 'bridge_account_profile_read_failure.dart';
import 'bridge_account_failure.dart';
import 'account_read_preparation.dart';
import 'bridge_account_staged_read.dart';
import 'bridge_account_legacy_snapshot.dart';
import 'bridge_account_legacy_presentation.dart';
import 'account_avatar_read_preparation.dart';
import 'account_restore_display.dart';

final class BridgeAccountAdapter
    implements
        AccountPort,
        AccountReadPreparationPort,
        AccountAvatarReadPreparationPort,
        AccountRestoreDisplayPort,
        LegacyProfileMigrationPort,
        PasswordRecoveryPort,
        LegacyPasswordLoginPort {
  BridgeAccountAdapter(this._session) {
    _eventSubscription = _session.events.listen(_onBridgeEvent);
  }

  final BridgeClientSession _session;
  final StreamController<AccountInvalidation> _invalidations =
      StreamController<AccountInvalidation>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _eventSubscription;
  BridgeAccountContext? _accountContext;
  AccountHostSnapshot? _lastSnapshot;
  AccountProfileReadSnapshot? _profileReadSnapshot;
  late final _stagedReads = AccountStagedRead(_session);
  late final _avatarReads = AccountAvatarReadPreparation(_session);
  late final _restoreDisplay = AccountRestoreDisplay(_session);
  @override
  AccountRestoreDisplay get restoreDisplay => _restoreDisplay;
  @override
  bool get supportsAvatarReadPreparation =>
      supportsStagedReads &&
      _session.hostCapabilities.contains('account.avatar.read');
  @override
  void cancelAvatarReadPreparation() => _avatarReads.cancel();
  @override
  Future<AccountAvatarReadResult?> prepareAvatarRead({
    bool retry = false,
  }) async {
    final snapshot = _lastSnapshot, owner = _accountContext;
    if (!supportsAvatarReadPreparation ||
        snapshot == null ||
        owner == null ||
        snapshot.sessionState != AccountSessionState.signedIn) {
      return null;
    }
    final result = await _avatarReads.read(
      owner,
      snapshot.generation,
      retry: retry,
    );
    final latest = _lastSnapshot;
    if (result?.hasPresentation == true &&
        latest != null &&
        result!.matches(latest.route, latest.generation)) {
      _lastSnapshot = latest.copyWith(profile: result.apply(latest.profile));
    }
    return result;
  }

  @override
  bool get supportsStagedReads => _stagedReads.supported;
  @override
  bool get hasPendingReadPreparation => _stagedReads.hasPending;
  @override
  bool get shouldRetryReadPreparation => _stagedReads.shouldRetry;
  @override
  void cancelReadPreparation() => _stagedReads.cancel();
  @override
  Future<AccountPortResult?> prepareNextRead({bool retry = false}) async {
    final current = _lastSnapshot;
    if (current == null || !supportsStagedReads) return null;
    final revision = _stagedReads.revision;
    final result = await _stagedReads.prepare(
      current,
      _profileReadSnapshot,
      retry: retry,
    );
    var next = result?.snapshot;
    if (revision != _stagedReads.revision ||
        next != null && next.generation != _session.activeGeneration) {
      return null;
    }
    if (next == null) return result;
    final avatar = _avatarReads.confirmed;
    if (next.sessionState != AccountSessionState.signedIn ||
        next.profile == null && result?.failure != null) {
      _avatarReads.invalidate();
    } else if (avatar != null && avatar.matches(next.route, next.generation)) {
      next = next.copyWith(profile: avatar.apply(next.profile));
    }
    _lastSnapshot = next;
    if (next.sessionState != AccountSessionState.signedIn) {
      _accountContext = null;
    }
    _profileReadSnapshot = AccountProfileReadSnapshot.capture(
      next,
      _stagedReads.observedAtUtc,
    );
    return AccountPortResult(
      outcome: result!.outcome,
      snapshot: next,
      failure: result.failure,
    );
  }

  BridgeRequestOperation? _compatibilityOperation;
  BridgeRequestOperation? _recoveryOperation;
  BridgeRequestOperation? _legacyLoginOperation;
  @override
  bool get supportsLegacyPasswordLogin =>
      _session.hostCapabilities.contains('account.legacyLogin');
  @override
  Future<void> cancelLegacyPasswordLogin() async {
    await _legacyLoginOperation?.cancel();
  }

  @override
  Future<LegacyPasswordLoginResult> loginLegacy(
    String email,
    String password,
  ) async {
    if (!supportsLegacyPasswordLogin) {
      return const LegacyPasswordLoginResult('unavailable');
    }
    if (_legacyLoginOperation != null) {
      return const LegacyPasswordLoginResult('busy');
    }
    if (_accountContext != null) {
      return const LegacyPasswordLoginResult('sessionChanged');
    }
    final operationGeneration = _session.activeGeneration;
    final operation = _session.beginRequest(
      'account.loginLegacy',
      payload: {
        'schemaVersion': 1,
        'email': email.trim(),
        'password': password,
      },
      timeout: const Duration(seconds: 35),
    );
    _legacyLoginOperation = operation;
    try {
      final response = await operation.future;
      AccountPayloadDecoder.requireSchema(response.payload);
      const outcomes = {
        'verified',
        'rejected',
        'scmRequired',
        'retired',
        'invalidInput',
        'throttled',
        'unavailable',
        'storageUnavailable',
        'busy',
        'sessionChanged',
      };
      final outcome = response.payload['outcome'];
      if (outcome is! String || !outcomes.contains(outcome)) {
        return const LegacyPasswordLoginResult('unavailable');
      }
      final retry = response.payload['retryAfterSeconds'];
      // Updated Hosts publish a distinct Relay session after the response.
      // Older verification-only Hosts do not promise an account.changed event.
      if (outcome == 'verified' &&
          _session.hostCapabilities.contains('account.legacySession')) {
        await waitForAccountGenerationAdvance(_session, operationGeneration);
      }
      // Never parse an SCM session/context from a legacy-password response.
      return LegacyPasswordLoginResult(
        outcome,
        retryAfterSeconds: retry is int ? retry.clamp(0, 3600) : 0,
      );
    } on BridgeCancelledException {
      return const LegacyPasswordLoginResult('cancelled');
    } on Object {
      return const LegacyPasswordLoginResult('unavailable');
    } finally {
      if (identical(_legacyLoginOperation, operation)) {
        _legacyLoginOperation = null;
      }
    }
  }

  @override
  bool get supportsPasswordRecovery =>
      _session.hostCapabilities.contains('account.passwordRecovery');
  @override
  Future<PasswordRecoveryResult> sendPasswordResetCode(String email) =>
      _recoverPassword('account.sendPasswordResetCode', {
        'email': email.trim(),
      });
  @override
  Future<PasswordRecoveryResult> confirmPasswordReset(
    String email,
    String code,
    String password,
  ) => _recoverPassword('account.confirmPasswordReset', {
    'email': email.trim(),
    'verificationCode': code.trim(),
    'newPassword': password,
  });
  @override
  Future<void> cancelPasswordRecovery() async {
    await _recoveryOperation?.cancel();
  }

  Future<PasswordRecoveryResult> _recoverPassword(
    String action,
    Map<String, Object?> fields,
  ) async {
    if (!supportsPasswordRecovery) {
      return const PasswordRecoveryResult('unavailable');
    }
    if (_recoveryOperation != null) return const PasswordRecoveryResult('busy');
    final operation = _session.beginRequest(
      action,
      payload: {'schemaVersion': 1, ...fields},
      timeout: const Duration(seconds: 30),
    );
    _recoveryOperation = operation;
    try {
      final response = await operation.future;
      AccountPayloadDecoder.requireSchema(response.payload);
      const outcomes = {
        'codeRequested',
        'reset',
        'invalidEmail',
        'invalidCode',
        'invalidPassword',
        'commonPassword',
        'throttled',
        'unavailable',
        'busy',
      };
      final outcome = response.payload['outcome'];
      if (outcome is! String ||
          !outcomes.contains(outcome) ||
          (outcome == 'reset' && action != 'account.confirmPasswordReset') ||
          (outcome == 'codeRequested' &&
              action != 'account.sendPasswordResetCode')) {
        return const PasswordRecoveryResult('unavailable');
      }
      final retry = response.payload['retryAfterSeconds'];
      return PasswordRecoveryResult(
        outcome,
        retryAfterSeconds: retry is int ? retry.clamp(0, 3600) : 0,
      );
    } on BridgeCancelledException {
      return const PasswordRecoveryResult('cancelled');
    } on Object {
      return const PasswordRecoveryResult('unavailable');
    } finally {
      if (identical(_recoveryOperation, operation)) _recoveryOperation = null;
    }
  }

  // Host restore/profile reads aggregate multiple individually bounded HTTP
  // requests. Let the Host report their outcome before the Bridge deadline.
  static const _snapshotReadTimeout = Duration(seconds: 60);

  @override
  Future<LegacyProfileMigrationView> migrationStatus() =>
      _migration('migrationStatus');
  @override
  Future<LegacyProfileMigrationView> previewMigration({
    LegacyAccountCredential? credential,
    LegacyProfileImportSelection? selection,
  }) => _migration('migrationPreview', {
    if (credential != null) 'accountName': credential.accountName,
    if (credential != null) 'password': credential.password,
    if (selection != null) 'selection': selection.toJson(),
  });
  @override
  Future<LegacyProfileMigrationView> confirmMigration(
    String previewId, {
    required bool replaceExisting,
  }) => _migration('migrationConfirm', {
    'previewId': previewId,
    'replaceExisting': replaceExisting,
  });

  Future<LegacyProfileMigrationView> _migration(
    String action, [
    Map<String, Object?> fields = const {},
  ]) async {
    try {
      final generation = _session.activeGeneration;
      final response = await _session.request(
        'personalProfile.$action',
        payload: {'schemaVersion': 1, ...fields},
        accountContext: _requiredContext(),
        timeout: action == 'migrationConfirm'
            ? const Duration(minutes: 4)
            : const Duration(seconds: 60),
      );
      if (generation != _session.activeGeneration) {
        return const LegacyProfileMigrationView('authorizationRequired');
      }
      final data = response.payload['migration'];
      if (response.payload['schemaVersion'] != 1 ||
          data is! Map<String, Object?>) {
        throw const FormatException('Invalid migration response.');
      }
      return LegacyProfileMigrationView.fromJson(data);
    } on BridgeRemoteException catch (error) {
      return LegacyProfileMigrationView(
        error.code == 'account.reauthorization_required'
            ? 'authorizationRequired'
            : 'sourceUnavailable',
      );
    } on Object {
      return const LegacyProfileMigrationView('sourceUnavailable');
    }
  }

  @override
  Stream<AccountInvalidation> get invalidations => _invalidations.stream;

  @override
  Future<AccountPortResult> read() {
    _avatarReads.allowReread();
    return _read(retryGenerationChange: true);
  }

  Future<AccountPortResult> _read({required bool retryGenerationChange}) async {
    final generation = _session.activeGeneration;
    try {
      final accountEnvelope = await _restoreDisplay.read(_snapshotReadTimeout);
      final snapshot = await _readSnapshot(accountEnvelope);
      _restoreDisplay.confirmSnapshot(snapshot);
      _lastSnapshot = snapshot;
      if (snapshot.sessionState != AccountSessionState.signedIn) {
        _profileReadSnapshot = null;
      }
      return AccountPortResult.completed(snapshot);
    } on AccountProfileSnapshotFailure catch (error) {
      _restoreDisplay.confirmSnapshot(error.snapshot);
      _lastSnapshot = error.snapshot;
      if (error.snapshot.profile == null) _profileReadSnapshot = null;
      if (error.snapshot.sessionState != AccountSessionState.signedIn) {
        _accountContext = null;
      }
      return AccountPortResult(
        outcome: AccountActionOutcome.failed,
        snapshot: error.snapshot,
        failure: mapAccountBridgeFailure(error.cause),
      );
    } on Object catch (error) {
      // Restoring the Host can invalidate an in-flight read before the async
      // account.changed notification reaches the Module. Retry that read once
      // against the confirmed new generation, never replay a write.
      if (retryGenerationChange &&
          generation != _session.activeGeneration &&
          error is BridgeClientException &&
          error.code == 'bridge.stale_generation') {
        return _read(retryGenerationChange: false);
      }
      return AccountPortResult.failed(mapAccountBridgeFailure(error));
    }
  }

  @override
  Future<AccountPortResult> execute(AccountPortCommand command) async {
    try {
      _restoreDisplay.withdraw();
      if (command is SaveAccountPreferences) {
        _stagedReads.cancel();
      } else {
        _stagedReads.clear();
      }
      final generationBeforeCommand = _session.activeGeneration;
      final commandContext = _accountContext;
      AccountCompatibilityProjection? confirmedCompatibility;
      final advancesGeneration =
          command is BeginAccountLogin || command is LogoutAccount;
      switch (command) {
        case BeginAccountLogin():
          await _session.request(
            'account.login',
            payload: const {'schemaVersion': 1},
            timeout: const Duration(minutes: 3),
          );
        case CancelAccountLogin():
          await _session.request(
            'account.cancelLogin',
            payload: const {'schemaVersion': 1},
          );
        case LogoutAccount():
          await _session.request(
            'account.logout',
            payload: const {'schemaVersion': 1},
            accountContext: _requiredContext(),
          );
        case SaveAccountPreferences(:final patch):
          if (_lastSnapshot?.supportsPreferenceWrite != true) {
            throw const BridgeClientException('bridge.capability_unavailable');
          }
          if (patch.isEmpty) {
            throw const BridgeFormatException(
              'Profile preference patch must not be empty.',
            );
          }
          final response = await _session.request(
            'profile.patchPreferences',
            payload: {
              'schemaVersion': 1,
              'patch': {
                if (patch.localeSpecified) 'locale': patch.locale,
                if (patch.timeZoneSpecified) 'timeZone': patch.timeZone,
              },
            },
            accountContext: _requiredContext(),
            timeout: const Duration(minutes: 4),
          );
          final current = _requireActionSnapshot(generationBeforeCommand);
          final confirmation = decodeAccountPreferenceConfirmation(
            current,
            response.payload,
          );
          _lastSnapshot = confirmation.snapshot;
          _profileReadSnapshot = AccountProfileReadSnapshot.capture(
            _lastSnapshot!,
            confirmation.observedAtUtc,
          );
          _stagedReads.observedAtUtc = _profileReadSnapshot?.observedAtUtc;
          return AccountPortResult.completed(_lastSnapshot!);
        case ClearAccountProfileCache():
          if (_lastSnapshot?.supportsCacheClear != true) {
            throw const BridgeClientException('bridge.capability_unavailable');
          }
          final response = await _session.request(
            'profile.clearLocalCache',
            payload: const {'schemaVersion': 1},
            accountContext: _requiredContext(),
          );
          AccountPayloadDecoder.requireSchema(response.payload);
          if (response.payload['cleared'] is! bool) {
            throw const BridgeFormatException('Cache clear result is missing.');
          }
          _profileReadSnapshot = null;
          _avatarReads.invalidate();
          final current = _requireActionSnapshot(generationBeforeCommand);
          _lastSnapshot =
              supportsStagedReads &&
                  current.profileFreshness == AccountProfileFreshness.cached
              ? current.copyWith(
                  clearProfile: true,
                  profileFreshness: AccountProfileFreshness.unavailable,
                  clearCachedAt: true,
                  timeZoneOptions: const [],
                  supportsPreferenceWrite: false,
                )
              : current;
          return AccountPortResult.completed(_lastSnapshot!);
        case LinkLegacyAccount(:final credential):
          if (!_session.hostCapabilities.contains(
                'account.compatibility.linkExisting',
              ) ||
              _lastSnapshot?.compatibility.availableActions.contains(
                    AccountCompatibilityAction.linkExistingAccount,
                  ) !=
                  true) {
            throw const BridgeClientException('bridge.capability_unavailable');
          }
          if (credential == null ||
              credential.accountName.trim().isEmpty ||
              credential.password.isEmpty) {
            throw const BridgeClientException(
              'account.legacy_credentials_required',
            );
          }
          if (_compatibilityOperation != null) {
            throw const BridgeClientException('account.operation_in_progress');
          }
          final operation = _session.beginRequest(
            'account.linkLegacyAccount',
            payload: {
              'schemaVersion': 1,
              'credential': {
                'accountName': credential.accountName.trim(),
                'password': credential.password,
              },
            },
            accountContext: _requiredContext(),
            timeout: const Duration(minutes: 4),
          );
          _compatibilityOperation = operation;
          try {
            final response = await operation.future;
            _requireActionSnapshot(generationBeforeCommand);
            confirmedCompatibility = AccountPayloadDecoder.compatibility(
              response.payload,
              canLinkExisting: _session.hostCapabilities.contains(
                'account.compatibility.linkExisting',
              ),
            );
            if (confirmedCompatibility.identityState !=
                AccountCompatibilityIdentityState.linked) {
              throw const BridgeFormatException(
                'Existing-account link was not confirmed.',
              );
            }
          } finally {
            if (identical(_compatibilityOperation, operation)) {
              _compatibilityOperation = null;
            }
          }
        case CancelCompatibilityOperation():
          final operation = _compatibilityOperation;
          if (operation == null) {
            throw const BridgeClientException('bridge.capability_unavailable');
          }
          await operation.cancel();
          // Re-read: a proof may already have been consumed before cancellation.
          return await read();
        case CreateCompatibilityIdentity():
          // Registration/provisioning remains closed even on link-capable Hosts.
          throw const BridgeClientException('bridge.capability_unavailable');
      }
      if (advancesGeneration) {
        await waitForAccountGenerationAdvance(
          _session,
          generationBeforeCommand,
        );
      }
      final refreshed = await read();
      final next = refreshed.snapshot;
      if (confirmedCompatibility != null &&
          commandContext != null &&
          refreshed.outcome == AccountActionOutcome.completed &&
          next != null &&
          next.sessionState == AccountSessionState.signedIn &&
          next.generation == generationBeforeCommand &&
          _session.activeGeneration == generationBeforeCommand &&
          next.route?.environment == commandContext.environment &&
          next.route?.authority == commandContext.authority &&
          next.route?.subject == commandContext.subject) {
        _lastSnapshot = next.copyWith(compatibility: confirmedCompatibility);
        return AccountPortResult.completed(_lastSnapshot!);
      }
      return refreshed;
    } on BridgeCancelledException {
      final snapshot = _lastSnapshot;
      return snapshot == null
          ? const AccountPortResult.failed(
              AccountFailure(
                code: 'bridge.cancelled',
                messageKey: 'account.login.cancelled',
                retryable: false,
              ),
            )
          : AccountPortResult.cancelled(snapshot);
    } on Object catch (error) {
      return AccountPortResult.failed(mapAccountBridgeFailure(error));
    }
  }

  AccountHostSnapshot _requireActionSnapshot(int generation) {
    final snapshot = _lastSnapshot;
    if (snapshot == null ||
        snapshot.generation != generation ||
        _session.activeGeneration != generation) {
      throw BridgeStaleGenerationException(
        generation,
        _session.activeGeneration,
      );
    }
    return snapshot;
  }

  Future<AccountHostSnapshot> _readSnapshot(
    BridgeEnvelope accountEnvelope,
  ) async {
    if (accountEnvelope.sessionGeneration != _session.activeGeneration) {
      throw BridgeStaleGenerationException(
        accountEnvelope.sessionGeneration,
        _session.activeGeneration,
      );
    }
    final sessionState = AccountPayloadDecoder.sessionState(
      accountEnvelope.payload,
    );
    if (sessionState == AccountSessionState.legacySignedIn ||
        sessionState == AccountSessionState.legacyUnavailable) {
      _stagedReads.clear();
      return readLegacyAccountSnapshot(
        _session,
        accountEnvelope,
        sessionState,
        (context) => _accountContext = context,
      );
    }
    if (sessionState == AccountSessionState.signedOut ||
        sessionState == AccountSessionState.credentialTemporarilyUnavailable ||
        sessionState == AccountSessionState.reauthorizationRequired) {
      _accountContext = null;
      _stagedReads.clear();
      final retained = AccountPayloadDecoder.retainedDisplay(
        accountEnvelope,
        sessionState,
      );
      return AccountHostSnapshot(
        generation: accountEnvelope.sessionGeneration,
        sessionState: sessionState,
        profile: retained?.profile,
        cachedAt: retained?.cachedAt,
        retainedReadId: retained?.readId,
        retainedPreviousReadId: retained?.previousReadId,
        profileFreshness: retained == null
            ? AccountProfileFreshness.unavailable
            : AccountProfileFreshness.cached,
        identity: const AccountIdentityProjection.unavailable(),
        compatibility: const AccountCompatibilityProjection.unavailable(),
        localeOptions: const [],
        timeZoneOptions: const [],
      );
    }

    final context = accountEnvelope.accountContext;
    if (context == null) {
      throw const BridgeFormatException(
        'Signed-in account response requires accountContext.',
      );
    }
    _accountContext = context;
    if (supportsStagedReads) {
      final snapshot = await _stagedReads.readCached(
        accountEnvelope,
        _lastSnapshot,
        _profileReadSnapshot,
      );
      _profileReadSnapshot = AccountProfileReadSnapshot.capture(
        snapshot,
        _stagedReads.observedAtUtc,
      );
      return snapshot;
    }
    final route = AccountRoute(
      environment: context.environment,
      authority: context.authority,
      subject: context.subject,
    );

    AccountProfile? profile;
    var freshness = AccountProfileFreshness.unavailable;
    DateTime? cachedAt;
    var localeOptions = const <String>[];
    var timeZoneOptions = const <AccountTimeZoneOption>[];
    var identity = const AccountIdentityProjection.unavailable();

    AccountProfilePayload profileData;
    try {
      final profileEnvelope = await _session.request(
        'profile.getSelf',
        payload: const {'schemaVersion': 1},
        accountContext: context,
        timeout: _snapshotReadTimeout,
      );
      profileData = AccountPayloadDecoder.profile(profileEnvelope.payload);
    } on Object catch (error) {
      if (error is BridgeStaleGenerationException ||
          _session.activeGeneration != accountEnvelope.sessionGeneration) {
        rethrow;
      }
      throw AccountProfileSnapshotFailure(
        accountProfileReadFailureSnapshot(
          error: error,
          generation: accountEnvelope.sessionGeneration,
          route: route,
          previous: _profileReadSnapshot,
        ),
        error,
      );
    }
    final profileObservedAtUtc =
        profileData.observedAt ??
        profileData.cachedAt ??
        DateTime.now().toUtc();
    _profileReadSnapshot = AccountProfileReadSnapshot(
      route,
      accountEnvelope.sessionGeneration,
      profileData.profile,
      profileObservedAtUtc,
    );
    profile = profileData.profile;
    profile = await readLegacyAccountAvatar(
      _session,
      context,
      accountEnvelope,
      profile,
      _snapshotReadTimeout,
    );
    freshness = profileData.freshness;
    cachedAt = profileData.cachedAt;
    localeOptions = profileData.localeOptions;
    timeZoneOptions = profileData.timeZoneOptions;

    _profileReadSnapshot = AccountProfileReadSnapshot(
      route,
      accountEnvelope.sessionGeneration,
      profile,
      profileObservedAtUtc,
    );
    final identityEnvelope = await _session.request(
      'gameIdentity.getPolicy',
      payload: const {'schemaVersion': 1},
      accountContext: context,
      // This local policy shares the Host account queue with network reads.
      timeout: _snapshotReadTimeout,
    );
    identity = AccountPayloadDecoder.identity(identityEnvelope.payload);

    final compatibility = await readLegacyAccountCompatibility(
      _session,
      context,
      _snapshotReadTimeout,
    );

    if (_session.activeGeneration != accountEnvelope.sessionGeneration) {
      throw BridgeStaleGenerationException(
        accountEnvelope.sessionGeneration,
        _session.activeGeneration,
      );
    }

    return AccountHostSnapshot(
      generation: accountEnvelope.sessionGeneration,
      sessionState: AccountSessionState.signedIn,
      route: route,
      profile: profile,
      profileFreshness: freshness,
      cachedAt: cachedAt,
      identity: identity,
      compatibility: compatibility,
      localeOptions: localeOptions,
      timeZoneOptions: timeZoneOptions,
      supportsPreferenceWrite: profileData.supportsPreferenceWrite,
      supportsCacheClear: profileData.supportsCacheClear,
    );
  }

  BridgeAccountContext _requiredContext() {
    return _accountContext ??
        (throw const BridgeAccountContextRequiredException('account feature'));
  }

  void _onBridgeEvent(BridgeEnvelope event) {
    _restoreDisplay.observeEvent(event);
    if (event.name == 'account.changed' ||
        event.name == 'bootstrap.invalidated') {
      _profileReadSnapshot = null;
      _stagedReads.clear();
      _avatarReads.cancel();
      if (event.sessionGeneration != _lastSnapshot?.generation) {
        _lastSnapshot = null;
      }
    }
    if (event.name == 'account.changed' ||
        event.name == 'account.avatarChanged' ||
        event.name == 'account.presentationChanged' ||
        event.name == 'personalProfile.changed' ||
        event.name == 'bootstrap.invalidated' ||
        event.name == 'gameIdentity.changed') {
      _avatarReads.invalidate();
      _invalidations.add(
        AccountInvalidation(generation: event.sessionGeneration),
      );
    }
  }

  @override
  Future<void> close() async {
    _restoreDisplay.dispose();
    _stagedReads.clear();
    _avatarReads.cancel();
    await cancelLegacyPasswordLogin();
    await cancelPasswordRecovery();
    await _compatibilityOperation?.cancel();
    await _eventSubscription.cancel();
    await _invalidations.close();
  }
}
