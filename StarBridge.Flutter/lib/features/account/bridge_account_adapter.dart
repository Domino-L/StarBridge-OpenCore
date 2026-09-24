import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'account_models.dart';
import 'account_port.dart';
import 'account_payload_decoder.dart';
import 'legacy_profile_migration.dart';
import 'password_recovery.dart';
import 'legacy_password_login.dart';

final class BridgeAccountAdapter
    implements
        AccountPort,
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
        await _waitForGenerationAdvance(operationGeneration);
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
  }) => _migration('migrationPreview', {
    if (credential != null) 'accountName': credential.accountName,
    if (credential != null) 'password': credential.password,
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
  Future<AccountPortResult> read() => _read(retryGenerationChange: true);

  Future<AccountPortResult> _read({required bool retryGenerationChange}) async {
    final generation = _session.activeGeneration;
    try {
      final accountEnvelope = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
        timeout: _snapshotReadTimeout,
      );
      final snapshot = await _readSnapshot(accountEnvelope);
      _lastSnapshot = snapshot;
      return AccountPortResult.completed(snapshot);
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
      return AccountPortResult.failed(_mapFailure(error));
    }
  }

  @override
  Future<AccountPortResult> execute(AccountPortCommand command) async {
    try {
      final generationBeforeCommand = _session.activeGeneration;
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
          final data = AccountPayloadDecoder.profile(response.payload);
          _lastSnapshot = AccountHostSnapshot(
            generation: current.generation,
            sessionState: current.sessionState,
            route: current.route,
            profile: data.profile,
            profileFreshness: data.freshness,
            cachedAt: data.cachedAt,
            identity: current.identity,
            compatibility: current.compatibility,
            localeOptions: data.localeOptions,
            timeZoneOptions: data.timeZoneOptions,
            supportsPreferenceWrite: data.supportsPreferenceWrite,
            supportsCacheClear: data.supportsCacheClear,
          );
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
          return AccountPortResult.completed(
            _requireActionSnapshot(generationBeforeCommand),
          );
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
            if (AccountPayloadDecoder.compatibility(
                  response.payload,
                  canLinkExisting: _session.hostCapabilities.contains(
                    'account.compatibility.linkExisting',
                  ),
                ).identityState !=
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
        await _waitForGenerationAdvance(generationBeforeCommand);
      }
      final refreshed = await read();
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
      return AccountPortResult.failed(_mapFailure(error));
    }
  }

  Future<void> _waitForGenerationAdvance(int previousGeneration) async {
    if (_session.activeGeneration > previousGeneration) {
      return;
    }

    final completion = Completer<void>();
    late final StreamSubscription<BridgeEnvelope> subscription;
    subscription = _session.events.listen((_) {
      if (_session.activeGeneration > previousGeneration &&
          !completion.isCompleted) {
        completion.complete();
      }
    });
    if (_session.activeGeneration > previousGeneration &&
        !completion.isCompleted) {
      completion.complete();
    }
    try {
      await completion.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw const BridgeTimeoutException('account.changed'),
      );
    } finally {
      await subscription.cancel();
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
    final sessionState = AccountPayloadDecoder.sessionState(
      accountEnvelope.payload,
    );
    if (sessionState == AccountSessionState.legacySignedIn ||
        sessionState == AccountSessionState.legacyUnavailable) {
      final context = accountEnvelope.accountContext;
      if (context == null ||
          !context.authority.startsWith('starbridge-relay-')) {
        throw const BridgeFormatException(
          'Legacy account requires a distinct Relay authority.',
        );
      }
      _accountContext = context;
      var identity = const AccountIdentityProjection.unavailable();
      if (_session.hostCapabilities.contains('account.read')) {
        try {
          final policy = await _session.request(
            'gameIdentity.getPolicy',
            payload: const {'schemaVersion': 1},
            accountContext: context,
            timeout: _snapshotReadTimeout,
          );
          identity = AccountPayloadDecoder.identity(policy.payload);
        } on BridgeRemoteException {
          // Optional local identity must not invalidate a restored Relay session.
        }
      }
      if (_session.activeGeneration != accountEnvelope.sessionGeneration) {
        throw BridgeStaleGenerationException(
          accountEnvelope.sessionGeneration,
          _session.activeGeneration,
        );
      }
      return AccountHostSnapshot(
        generation: accountEnvelope.sessionGeneration,
        sessionState: sessionState,
        route: AccountRoute(
          environment: context.environment,
          authority: context.authority,
          subject: context.subject,
        ),
        profile: AccountProfile(
          displayName: accountEnvelope.payload['displayName'] as String?,
          maskedAccount: accountEnvelope.payload['maskedAccount'] as String?,
          avatarImageData:
              accountEnvelope.payload['avatarImageData'] as String?,
        ),
        profileFreshness: sessionState == AccountSessionState.legacySignedIn
            ? AccountProfileFreshness.live
            : AccountProfileFreshness.cached,
        identity: identity,
        compatibility: const AccountCompatibilityProjection.unavailable(),
        localeOptions: const [],
        timeZoneOptions: const [],
      );
    }
    if (sessionState == AccountSessionState.signedOut ||
        sessionState == AccountSessionState.credentialTemporarilyUnavailable ||
        sessionState == AccountSessionState.reauthorizationRequired) {
      _accountContext = null;
      return AccountHostSnapshot(
        generation: accountEnvelope.sessionGeneration,
        sessionState: sessionState,
        profileFreshness: AccountProfileFreshness.unavailable,
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

    final profileEnvelope = await _session.request(
      'profile.getSelf',
      payload: const {'schemaVersion': 1},
      accountContext: context,
      timeout: _snapshotReadTimeout,
    );
    final profileData = AccountPayloadDecoder.profile(profileEnvelope.payload);
    profile = profileData.profile;
    freshness = profileData.freshness;
    cachedAt = profileData.cachedAt;
    localeOptions = profileData.localeOptions;
    timeZoneOptions = profileData.timeZoneOptions;

    final identityEnvelope = await _session.request(
      'gameIdentity.getPolicy',
      payload: const {'schemaVersion': 1},
      accountContext: context,
      // This local policy shares the Host account queue with network reads.
      timeout: _snapshotReadTimeout,
    );
    identity = AccountPayloadDecoder.identity(identityEnvelope.payload);

    var compatibility = const AccountCompatibilityProjection.retired();
    if (_session.hostCapabilities.contains('account.compatibility.read')) {
      compatibility = const AccountCompatibilityProjection.unavailable();
      try {
        final response = await _session.request(
          'account.getCompatibilityState',
          payload: const {'schemaVersion': 1},
          accountContext: context,
          timeout: _snapshotReadTimeout,
        );
        compatibility = AccountPayloadDecoder.compatibility(
          response.payload,
          canLinkExisting: _session.hostCapabilities.contains(
            'account.compatibility.linkExisting',
          ),
        );
      } on BridgeRemoteException catch (error) {
        if (error.code != 'account.compatibility_read_unavailable' &&
            error.code != 'bridge.capability_unavailable') {
          rethrow;
        }
        // A compatibility service outage does not invalidate the SCM session.
      }
    }

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
    if (event.name == 'account.changed' ||
        event.name == 'account.avatarChanged' ||
        event.name == 'bootstrap.invalidated' ||
        event.name == 'gameIdentity.changed') {
      _invalidations.add(
        AccountInvalidation(generation: event.sessionGeneration),
      );
    }
  }

  AccountFailure _mapFailure(Object error) {
    if (error is BridgeClientException) {
      return AccountFailure(
        code: error.code,
        messageKey: _messageKeyForCode(error.code),
        retryable: error.retryable,
      );
    }
    if (error is BridgeFormatException) {
      return const AccountFailure(
        code: 'bridge.invalid_envelope',
        messageKey: 'account.error.invalidResponse',
        retryable: false,
      );
    }
    return const AccountFailure(
      code: 'account.unexpected',
      messageKey: 'account.error.unavailable',
      retryable: true,
    );
  }

  static String _messageKeyForCode(String code) => switch (code) {
    'bridge.disconnected' => 'account.error.hostUnavailable',
    'bridge.timeout' || 'account.login_timeout' => 'account.error.timeout',
    'bridge.cancelled' ||
    'account.login_cancelled' => 'account.login.cancelled',
    'bridge.stale_generation' => 'account.error.sessionChanged',
    'account.environment_not_enabled' => 'account.error.environmentNotEnabled',
    'account.reauthorization_required' =>
      'account.error.reauthorizationRequired',
    'profile.write_forbidden' => 'account.error.writeForbidden',
    'bridge.capability_unavailable' => 'account.action.unavailable',
    'profile.cache_clear_unavailable' => 'account.cache.failed',
    'profile.write_conflict' => 'account.error.writeConflict',
    'profile.directory_unavailable' => 'account.error.directoryUnavailable',
    'account.compatibility_read_unavailable' =>
      'account.error.compatibilityUnavailable',
    'account.compatibility_write_unavailable' =>
      'account.error.compatibilityWriteUnavailable',
    'account.compatibility_conflict' => 'account.error.compatibilityConflict',
    'account.compatibility_existing_link_mismatch' =>
      'account.error.compatibilityExistingLinkMismatch',
    'account.legacy_credentials_required' =>
      'account.error.legacyCredentialsRequired',
    'account.legacy_credentials_rejected' =>
      'account.error.legacyCredentialsRejected',
    'bridge.invalid_envelope' ||
    'bridge.protocol_incompatible' => 'account.error.invalidResponse',
    _ => 'account.error.unavailable',
  };

  @override
  Future<void> close() async {
    await cancelLegacyPasswordLogin();
    await cancelPasswordRecovery();
    await _compatibilityOperation?.cancel();
    await _eventSubscription.cancel();
    await _invalidations.close();
  }
}
