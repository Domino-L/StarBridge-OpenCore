import 'package:flutter/foundation.dart';

enum AccountSessionState {
  loading,
  signedOut,
  credentialTemporarilyUnavailable,
  signedIn,
  legacySignedIn,
  legacyUnavailable,
  reauthorizationRequired,
}

enum AccountProfileFreshness { unavailable, live, cached }

enum AccountIdentityState {
  unavailable,
  match,
  mismatch,
  awaitingGameIdentity,
  reverifyRequired,
  revoked,
  unknown,
}

enum AccountCompatibilityIdentityState {
  unavailable,
  unlinked,
  linked,
  unknown,
}

enum AccountCompatibilityRelayState {
  unavailable,
  notApplicable,
  notEstablished,
  ready,
  authorizationRequired,
  accountMismatch,
  unknown,
}

enum AccountCompatibilityAction {
  linkExistingAccount,
  createCompatibilityIdentity,
  retry,
}

enum AccountOperation {
  none,
  refreshing,
  signingIn,
  cancellingLogin,
  signingOut,
  linkingLegacyAccount,
  creatingCompatibilityIdentity,
  cancellingCompatibilityOperation,
  savingPreferences,
  clearingCache,
}

enum AccountActionOutcome { completed, cancelled, rejected, failed, stale }

enum AccountNoticeKind { information, success, warning, failure }

@immutable
final class AccountRoute {
  const AccountRoute({
    required this.environment,
    required this.authority,
    required this.subject,
  });

  final String environment;
  final String authority;
  final String subject;

  bool get isComplete =>
      environment.trim().isNotEmpty &&
      authority.trim().isNotEmpty &&
      subject.trim().isNotEmpty;
}

@immutable
final class AccountProfile {
  const AccountProfile({
    this.displayName,
    this.avatarUrl,
    this.avatarImageData,
    this.email,
    this.maskedAccount,
    this.locale,
    this.timeZone,
  });

  final String? displayName;
  final String? avatarUrl;
  final String? avatarImageData;
  final String? email;
  final String? maskedAccount;
  final String? locale;
  final String? timeZone;

  AccountProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? email,
    String? locale,
    String? timeZone,
    bool clearLocale = false,
    bool clearTimeZone = false,
  }) {
    return AccountProfile(
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarImageData: avatarImageData,
      email: email ?? this.email,
      maskedAccount: maskedAccount,
      locale: clearLocale ? null : locale ?? this.locale,
      timeZone: clearTimeZone ? null : timeZone ?? this.timeZone,
    );
  }
}

@immutable
final class AccountIdentityProjection {
  const AccountIdentityProjection({
    required this.state,
    required this.sensitiveWritesAllowed,
    this.authoritativeHandle,
  });

  const AccountIdentityProjection.unavailable()
    : state = AccountIdentityState.unavailable,
      sensitiveWritesAllowed = false,
      authoritativeHandle = null;

  final AccountIdentityState state;
  final bool sensitiveWritesAllowed;
  final String? authoritativeHandle;
}

@immutable
final class AccountCompatibilityProjection {
  const AccountCompatibilityProjection({
    required this.identityState,
    required this.relayState,
    required this.storedLegacyCredentialAvailable,
    required this.legacyFeaturesAvailable,
    required this.availableActions,
  });

  const AccountCompatibilityProjection.retired()
    : identityState = AccountCompatibilityIdentityState.unavailable,
      relayState = AccountCompatibilityRelayState.notApplicable,
      storedLegacyCredentialAvailable = false,
      legacyFeaturesAvailable = false,
      availableActions = const [];

  const AccountCompatibilityProjection.unavailable()
    : identityState = AccountCompatibilityIdentityState.unavailable,
      relayState = AccountCompatibilityRelayState.unavailable,
      storedLegacyCredentialAvailable = false,
      legacyFeaturesAvailable = false,
      availableActions = const [];

  final AccountCompatibilityIdentityState identityState;
  final AccountCompatibilityRelayState relayState;
  final bool storedLegacyCredentialAvailable;
  final bool legacyFeaturesAvailable;
  final List<AccountCompatibilityAction> availableActions;
}

@immutable
final class AccountTimeZoneOption {
  const AccountTimeZoneOption({
    required this.value,
    required this.label,
    required this.offset,
  });

  final String value;
  final String label;
  final String offset;
}

@immutable
final class AccountHostSnapshot {
  const AccountHostSnapshot({
    required this.generation,
    required this.sessionState,
    required this.profileFreshness,
    required this.identity,
    required this.compatibility,
    required this.localeOptions,
    required this.timeZoneOptions,
    this.route,
    this.profile,
    this.cachedAt,
    this.supportsPreferenceWrite = false,
    this.supportsCacheClear = false,
  });

  const AccountHostSnapshot.signedOut({required int generation})
    : this(
        generation: generation,
        sessionState: AccountSessionState.signedOut,
        profileFreshness: AccountProfileFreshness.unavailable,
        identity: const AccountIdentityProjection.unavailable(),
        compatibility: const AccountCompatibilityProjection.unavailable(),
        localeOptions: const [],
        timeZoneOptions: const [],
      );

  final int generation;
  final AccountSessionState sessionState;
  final AccountRoute? route;
  final AccountProfile? profile;
  final AccountProfileFreshness profileFreshness;
  final DateTime? cachedAt;
  final AccountIdentityProjection identity;
  final AccountCompatibilityProjection compatibility;
  final List<String> localeOptions;
  final List<AccountTimeZoneOption> timeZoneOptions;

  final bool supportsPreferenceWrite;
  final bool supportsCacheClear;

  String get accountLabel => profile?.displayName?.trim().isNotEmpty == true
      ? profile!.displayName!.trim()
      : '';
}

@immutable
final class AccountFailure {
  const AccountFailure({
    required this.code,
    required this.messageKey,
    required this.retryable,
  });

  final String code;
  final String messageKey;
  final bool retryable;
}

@immutable
final class AccountNotice {
  const AccountNotice({required this.kind, required this.messageKey});

  final AccountNoticeKind kind;
  final String messageKey;
}

@immutable
final class AccountProjection {
  const AccountProjection({
    required this.sessionState,
    required this.operation,
    required this.generation,
    required this.profileFreshness,
    required this.identity,
    required this.compatibility,
    required this.localeOptions,
    required this.timeZoneOptions,
    this.profile,
    this.cachedAt,
    this.failure,
    this.notice,
    this.supportsPreferenceWrite = false,
    this.supportsCacheClear = false,
  });

  const AccountProjection.loading()
    : this(
        sessionState: AccountSessionState.loading,
        operation: AccountOperation.refreshing,
        generation: 0,
        profileFreshness: AccountProfileFreshness.unavailable,
        identity: const AccountIdentityProjection.unavailable(),
        compatibility: const AccountCompatibilityProjection.unavailable(),
        localeOptions: const [],
        timeZoneOptions: const [],
      );

  final AccountSessionState sessionState;
  final AccountOperation operation;
  final int generation;
  final AccountProfile? profile;
  final AccountProfileFreshness profileFreshness;
  final DateTime? cachedAt;
  final AccountIdentityProjection identity;
  final AccountCompatibilityProjection compatibility;
  final List<String> localeOptions;
  final List<AccountTimeZoneOption> timeZoneOptions;
  final AccountFailure? failure;
  final AccountNotice? notice;
  final bool supportsPreferenceWrite;
  final bool supportsCacheClear;

  bool get isBusy => operation != AccountOperation.none;
  bool get isSignedIn => sessionState == AccountSessionState.signedIn;
  bool get isLegacyAccount =>
      sessionState == AccountSessionState.legacySignedIn ||
      sessionState == AccountSessionState.legacyUnavailable;
  bool get canLogin =>
      !isBusy &&
      (isLegacyAccount ||
          sessionState == AccountSessionState.signedOut ||
          sessionState == AccountSessionState.reauthorizationRequired);
  bool get canRetrySessionRestore =>
      !isBusy &&
      sessionState == AccountSessionState.credentialTemporarilyUnavailable;
  bool get canLogout => !isBusy && (isSignedIn || isLegacyAccount);
  bool get canEditPreferences =>
      !isBusy &&
      isSignedIn &&
      supportsPreferenceWrite &&
      profile != null &&
      profileFreshness == AccountProfileFreshness.live;
  bool get canClearProfileCache => !isBusy && isSignedIn && supportsCacheClear;
  bool get canLinkLegacyAccount =>
      !isBusy &&
      isSignedIn &&
      compatibility.availableActions.contains(
        AccountCompatibilityAction.linkExistingAccount,
      );
  bool get canCreateCompatibilityIdentity =>
      !isBusy &&
      isSignedIn &&
      compatibility.availableActions.contains(
        AccountCompatibilityAction.createCompatibilityIdentity,
      );
  bool get canRetryCompatibility =>
      !isBusy &&
      isSignedIn &&
      compatibility.availableActions.contains(AccountCompatibilityAction.retry);
  bool get canCancelCompatibilityOperation =>
      operation == AccountOperation.linkingLegacyAccount ||
      operation == AccountOperation.creatingCompatibilityIdentity;

  AccountProjection copyWith({
    AccountSessionState? sessionState,
    AccountOperation? operation,
    int? generation,
    AccountProfile? profile,
    bool clearProfile = false,
    AccountProfileFreshness? profileFreshness,
    DateTime? cachedAt,
    bool clearCachedAt = false,
    AccountIdentityProjection? identity,
    AccountCompatibilityProjection? compatibility,
    List<String>? localeOptions,
    List<AccountTimeZoneOption>? timeZoneOptions,
    AccountFailure? failure,
    bool clearFailure = false,
    AccountNotice? notice,
    bool clearNotice = false,
  }) {
    return AccountProjection(
      sessionState: sessionState ?? this.sessionState,
      operation: operation ?? this.operation,
      generation: generation ?? this.generation,
      profile: clearProfile ? null : profile ?? this.profile,
      profileFreshness: profileFreshness ?? this.profileFreshness,
      cachedAt: clearCachedAt ? null : cachedAt ?? this.cachedAt,
      identity: identity ?? this.identity,
      compatibility: compatibility ?? this.compatibility,
      localeOptions: localeOptions ?? this.localeOptions,
      timeZoneOptions: timeZoneOptions ?? this.timeZoneOptions,
      failure: clearFailure ? null : failure ?? this.failure,
      notice: clearNotice ? null : notice ?? this.notice,
      supportsPreferenceWrite: supportsPreferenceWrite,
      supportsCacheClear: supportsCacheClear,
    );
  }

  factory AccountProjection.fromSnapshot(
    AccountHostSnapshot snapshot, {
    AccountOperation operation = AccountOperation.none,
    AccountFailure? failure,
    AccountNotice? notice,
  }) {
    return AccountProjection(
      sessionState: snapshot.sessionState,
      operation: operation,
      generation: snapshot.generation,
      profile: snapshot.profile,
      profileFreshness: snapshot.profileFreshness,
      cachedAt: snapshot.cachedAt,
      identity: snapshot.identity,
      compatibility: snapshot.compatibility,
      localeOptions: List.unmodifiable(snapshot.localeOptions),
      timeZoneOptions: List.unmodifiable(snapshot.timeZoneOptions),
      failure: failure,
      notice: notice,
      supportsPreferenceWrite: snapshot.supportsPreferenceWrite,
      supportsCacheClear: snapshot.supportsCacheClear,
    );
  }
}

@immutable
final class AccountActionResult {
  const AccountActionResult(this.outcome, {this.failure});

  final AccountActionOutcome outcome;
  final AccountFailure? failure;
}
