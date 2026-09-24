import 'dart:async';

import 'account_models.dart';
import 'account_port.dart';

enum AccountReviewState {
  signedOut,
  signedIn,
  cached,
  mismatch,
  reauthorizationRequired,
}

final class InMemoryAccountAdapter implements AccountPort {
  InMemoryAccountAdapter({
    AccountHostSnapshot? initial,
    this.holdLoginUntilCancelled = false,
    this.holdCompatibilityUntilCancelled = false,
  }) : _snapshot =
           initial ?? const AccountHostSnapshot.signedOut(generation: 0);

  factory InMemoryAccountAdapter.forReview(AccountReviewState state) {
    return InMemoryAccountAdapter(initial: _reviewSnapshot(state));
  }

  final bool holdLoginUntilCancelled;
  final bool holdCompatibilityUntilCancelled;
  final StreamController<AccountInvalidation> _invalidations =
      StreamController<AccountInvalidation>.broadcast();
  AccountHostSnapshot _snapshot;
  int readCount = 0;
  Completer<AccountPortResult>? _pendingLogin;
  Completer<AccountPortResult>? _pendingCompatibility;
  AccountFailure? nextFailure;
  final List<AccountPortCommand> commands = [];

  AccountHostSnapshot get snapshot => _snapshot;

  @override
  Stream<AccountInvalidation> get invalidations => _invalidations.stream;

  @override
  Future<AccountPortResult> read() async {
    readCount++;
    final failure = _consumeFailure();
    return failure == null
        ? AccountPortResult.completed(_snapshot)
        : AccountPortResult.failed(failure);
  }

  @override
  Future<AccountPortResult> execute(AccountPortCommand command) async {
    commands.add(command);
    final failure = _consumeFailure();
    if (failure != null) {
      return AccountPortResult.failed(failure);
    }
    return switch (command) {
      BeginAccountLogin() => _beginLogin(),
      CancelAccountLogin() => _cancelLogin(),
      LogoutAccount() => _logout(),
      SaveAccountPreferences(:final patch) => _save(patch),
      ClearAccountProfileCache() => _clearCache(),
      LinkLegacyAccount() => _beginCompatibility(),
      CreateCompatibilityIdentity() => _beginCompatibility(),
      CancelCompatibilityOperation() => _cancelCompatibility(),
    };
  }

  Future<AccountPortResult> _beginLogin() {
    if (!holdLoginUntilCancelled) {
      _snapshot = _signedInSnapshot(_snapshot.generation + 1);
      _invalidate();
      return Future.value(AccountPortResult.completed(_snapshot));
    }
    _pendingLogin ??= Completer<AccountPortResult>();
    return _pendingLogin!.future;
  }

  AccountPortResult _cancelLogin() {
    final pending = _pendingLogin;
    _pendingLogin = null;
    final result = AccountPortResult.cancelled(_snapshot);
    if (pending != null && !pending.isCompleted) {
      pending.complete(result);
    }
    return result;
  }

  AccountPortResult _logout() {
    _snapshot = AccountHostSnapshot.signedOut(
      generation: _snapshot.generation + 1,
    );
    _invalidate();
    return AccountPortResult.completed(_snapshot);
  }

  AccountPortResult _save(AccountPreferencePatch patch) {
    final profile = _snapshot.profile;
    if (_snapshot.sessionState != AccountSessionState.signedIn ||
        profile == null ||
        patch.isEmpty) {
      return const AccountPortResult.failed(
        AccountFailure(
          code: 'profile.write_rejected',
          messageKey: 'account.error.writeRejected',
          retryable: false,
        ),
      );
    }
    final updated = profile.copyWith(
      locale: patch.localeSpecified ? patch.locale : null,
      clearLocale: patch.localeSpecified && patch.locale == null,
      timeZone: patch.timeZoneSpecified ? patch.timeZone : null,
      clearTimeZone: patch.timeZoneSpecified && patch.timeZone == null,
    );
    _snapshot = AccountHostSnapshot(
      generation: _snapshot.generation,
      sessionState: _snapshot.sessionState,
      route: _snapshot.route,
      profile: updated,
      profileFreshness: AccountProfileFreshness.live,
      identity: _snapshot.identity,
      compatibility: _snapshot.compatibility,
      localeOptions: _snapshot.localeOptions,
      timeZoneOptions: _snapshot.timeZoneOptions,
      supportsPreferenceWrite: _snapshot.supportsPreferenceWrite,
      supportsCacheClear: _snapshot.supportsCacheClear,
    );
    return AccountPortResult.completed(_snapshot);
  }

  AccountPortResult _clearCache() {
    _snapshot = AccountHostSnapshot(
      generation: _snapshot.generation,
      sessionState: _snapshot.sessionState,
      route: _snapshot.route,
      profile: _snapshot.profile,
      profileFreshness:
          _snapshot.profileFreshness == AccountProfileFreshness.cached
          ? AccountProfileFreshness.unavailable
          : _snapshot.profileFreshness,
      identity: _snapshot.identity,
      compatibility: _snapshot.compatibility,
      localeOptions: _snapshot.localeOptions,
      timeZoneOptions: _snapshot.timeZoneOptions,
      supportsPreferenceWrite: _snapshot.supportsPreferenceWrite,
      supportsCacheClear: _snapshot.supportsCacheClear,
    );
    return AccountPortResult.completed(_snapshot);
  }

  Future<AccountPortResult> _beginCompatibility() {
    if (holdCompatibilityUntilCancelled) {
      _pendingCompatibility ??= Completer<AccountPortResult>();
      return _pendingCompatibility!.future;
    }
    _snapshot = _withLinkedCompatibility(_snapshot);
    return Future.value(AccountPortResult.completed(_snapshot));
  }

  AccountPortResult _cancelCompatibility() {
    final pending = _pendingCompatibility;
    _pendingCompatibility = null;
    final result = AccountPortResult.cancelled(_snapshot);
    if (pending != null && !pending.isCompleted) {
      pending.complete(result);
    }
    return result;
  }

  static AccountHostSnapshot _withLinkedCompatibility(
    AccountHostSnapshot snapshot,
  ) {
    return AccountHostSnapshot(
      generation: snapshot.generation,
      sessionState: snapshot.sessionState,
      route: snapshot.route,
      profile: snapshot.profile,
      profileFreshness: snapshot.profileFreshness,
      cachedAt: snapshot.cachedAt,
      identity: snapshot.identity,
      compatibility: const AccountCompatibilityProjection(
        identityState: AccountCompatibilityIdentityState.linked,
        relayState: AccountCompatibilityRelayState.notEstablished,
        storedLegacyCredentialAvailable: false,
        legacyFeaturesAvailable: false,
        availableActions: [],
      ),
      localeOptions: snapshot.localeOptions,
      timeZoneOptions: snapshot.timeZoneOptions,
      supportsPreferenceWrite: snapshot.supportsPreferenceWrite,
      supportsCacheClear: snapshot.supportsCacheClear,
    );
  }

  void replace(AccountHostSnapshot snapshot) {
    _snapshot = snapshot;
    _invalidate();
  }

  void _invalidate() {
    _invalidations.add(AccountInvalidation(generation: _snapshot.generation));
  }

  AccountFailure? _consumeFailure() {
    final failure = nextFailure;
    nextFailure = null;
    return failure;
  }

  @override
  Future<void> close() async {
    final pending = _pendingLogin;
    if (pending != null && !pending.isCompleted) {
      pending.complete(AccountPortResult.cancelled(_snapshot));
    }
    final compatibility = _pendingCompatibility;
    if (compatibility != null && !compatibility.isCompleted) {
      compatibility.complete(AccountPortResult.cancelled(_snapshot));
    }
    await _invalidations.close();
  }

  static AccountHostSnapshot _reviewSnapshot(AccountReviewState state) {
    return switch (state) {
      AccountReviewState.signedOut => const AccountHostSnapshot.signedOut(
        generation: 0,
      ),
      AccountReviewState.reauthorizationRequired => AccountHostSnapshot(
        generation: 2,
        sessionState: AccountSessionState.reauthorizationRequired,
        profileFreshness: AccountProfileFreshness.unavailable,
        identity: const AccountIdentityProjection.unavailable(),
        compatibility: const AccountCompatibilityProjection.unavailable(),
        localeOptions: const [],
        timeZoneOptions: const [],
      ),
      AccountReviewState.cached => _signedInSnapshot(
        2,
        freshness: AccountProfileFreshness.cached,
      ),
      AccountReviewState.mismatch => _signedInSnapshot(
        2,
        identityState: AccountIdentityState.mismatch,
      ),
      AccountReviewState.signedIn => _signedInSnapshot(2),
    };
  }

  static AccountHostSnapshot _signedInSnapshot(
    int generation, {
    AccountProfileFreshness freshness = AccountProfileFreshness.live,
    AccountIdentityState identityState = AccountIdentityState.match,
  }) {
    return AccountHostSnapshot(
      generation: generation,
      sessionState: AccountSessionState.signedIn,
      route: const AccountRoute(
        environment: 'synthetic',
        authority: 'scm-test',
        subject: 'synthetic-subject',
      ),
      profile: const AccountProfile(
        displayName: 'Aster Lin',
        avatarUrl: null,
        locale: 'zh-CN',
        timeZone: 'Asia/Shanghai',
      ),
      profileFreshness: freshness,
      cachedAt: freshness == AccountProfileFreshness.cached
          ? DateTime.utc(2026, 8, 31, 12, 0)
          : null,
      identity: AccountIdentityProjection(
        state: identityState,
        sensitiveWritesAllowed: identityState == AccountIdentityState.match,
        authoritativeHandle: 'Aster-Lin',
      ),
      compatibility: const AccountCompatibilityProjection(
        identityState: AccountCompatibilityIdentityState.unlinked,
        relayState: AccountCompatibilityRelayState.notApplicable,
        storedLegacyCredentialAvailable: false,
        legacyFeaturesAvailable: false,
        availableActions: [
          AccountCompatibilityAction.linkExistingAccount,
          AccountCompatibilityAction.createCompatibilityIdentity,
        ],
      ),
      localeOptions: const ['zh-CN', 'en-US'],
      supportsPreferenceWrite: true,
      supportsCacheClear: true,
      timeZoneOptions: const [
        AccountTimeZoneOption(
          value: 'Asia/Shanghai',
          label: 'Shanghai',
          offset: 'UTC+08:00',
        ),
        AccountTimeZoneOption(
          value: 'America/Regina',
          label: 'Regina',
          offset: 'UTC-06:00',
        ),
        AccountTimeZoneOption(value: 'UTC', label: 'UTC', offset: 'UTC+00:00'),
      ],
    );
  }
}
