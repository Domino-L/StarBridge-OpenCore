import '../../platform/bridge/bridge_envelope.dart';
import '../../shared/bounded_inline_avatar.dart';
import 'account_models.dart';

/// Validates host account payloads without owning transport or session state.
abstract final class AccountPayloadDecoder {
  /// Presentation only. This never produces an authenticated account context.
  static ({
    AccountProfile profile,
    DateTime cachedAt,
    String? readId,
    String? previousReadId,
  })?
  retainedDisplay(BridgeEnvelope envelope, AccountSessionState state) {
    final retained = envelope.payload['retainedDisplay'];
    if (retained == null) return null;
    if (state != AccountSessionState.credentialTemporarilyUnavailable ||
        envelope.accountContext != null ||
        retained is! Map<String, Object?> ||
        retained.keys.any(
          (key) => !const {
            'displayName',
            'cachedAtUtc',
            'readId',
            'previousReadId',
            'avatarImageData',
            'avatarCachedAtUtc',
          }.contains(key),
        ) ||
        retained['displayName'] is! String ||
        retained['cachedAtUtc'] is! String) {
      throw const BridgeFormatException('Invalid retained account display.');
    }
    final name = retained['displayName']! as String;
    final at = DateTime.tryParse(retained['cachedAtUtc']! as String);
    if (name.trim().isEmpty ||
        name.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
        at == null ||
        !at.isUtc ||
        !at.isAfter(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)) ||
        at.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))) {
      throw const BridgeFormatException('Invalid retained account display.');
    }
    final readId = retained['readId'];
    if (retained.containsKey('readId') &&
        (readId is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(readId))) {
      throw const BridgeFormatException('Invalid retained read selection.');
    }
    final previousReadId = retained['previousReadId'];
    if (retained.containsKey('previousReadId') &&
        (readId == null ||
            previousReadId is! String ||
            !RegExp(r'^[a-f0-9]{32}$').hasMatch(previousReadId) ||
            previousReadId == readId)) {
      throw const BridgeFormatException('Invalid retained display continuity.');
    }
    return (
      profile: AccountProfile(
        displayName: name,
        avatarImageData:
            inlineAvatarObservedAt(retained['avatarCachedAtUtc']) == null
            ? null
            : boundedInlineAvatar(retained['avatarImageData']),
      ),
      cachedAt: at,
      readId: readId as String?,
      previousReadId: previousReadId as String?,
    );
  }

  static void requireSchema(Map<String, Object?> payload) =>
      _requireSchema(payload);

  static AccountSessionState sessionState(Map<String, Object?> payload) {
    _requireSchema(payload);
    return _parseSessionState(_requiredString(payload, 'state'));
  }

  static AccountCompatibilityProjection compatibility(
    Map<String, Object?> payload, {
    required bool canLinkExisting,
  }) {
    _requireSchema(payload);
    final identity = switch (_requiredString(payload, 'identityState')) {
      'linked' => AccountCompatibilityIdentityState.linked,
      'unlinked' => AccountCompatibilityIdentityState.unlinked,
      _ => AccountCompatibilityIdentityState.unknown,
    };
    final relay = switch (_requiredString(payload, 'relayState')) {
      'ready' => AccountCompatibilityRelayState.ready,
      'notApplicable' => AccountCompatibilityRelayState.notApplicable,
      'notEstablished' => AccountCompatibilityRelayState.notEstablished,
      'accountMismatch' => AccountCompatibilityRelayState.accountMismatch,
      'authorizationRequired' =>
        AccountCompatibilityRelayState.authorizationRequired,
      'unavailable' => AccountCompatibilityRelayState.unavailable,
      _ => AccountCompatibilityRelayState.unknown,
    };
    return AccountCompatibilityProjection(
      identityState: identity,
      relayState: relay,
      storedLegacyCredentialAvailable:
          payload['storedLegacyCredentialAvailable'] == true,
      legacyFeaturesAvailable:
          identity == AccountCompatibilityIdentityState.linked &&
          relay == AccountCompatibilityRelayState.ready &&
          payload['legacyFeaturesAvailable'] == true,
      // Only the negotiated existing-account action may cross this boundary.
      availableActions: [
        if (identity == AccountCompatibilityIdentityState.unlinked &&
            canLinkExisting &&
            payload['availableActions'] is List &&
            (payload['availableActions'] as List).contains(
              'linkExistingAccount',
            ))
          AccountCompatibilityAction.linkExistingAccount,
      ],
    );
  }

  static AccountProfilePayload profile(
    Map<String, Object?> payload, {
    bool allowDirectoryOmission = false,
  }) {
    _requireSchema(payload);
    final profile = _requiredMap(payload, 'profile');
    final source = _requiredString(payload, 'source');
    final freshness = switch (source) {
      'live' => AccountProfileFreshness.live,
      'cache' => AccountProfileFreshness.cached,
      _ => throw const BridgeFormatException('Profile source is unsupported.'),
    };
    final cachedAtText = payload['cachedAtUtc'] as String?;
    final cachedAt = cachedAtText == null
        ? null
        : DateTime.tryParse(cachedAtText);
    final observedText = payload['observedAtUtc'];
    final observedAt = observedText is String
        ? DateTime.tryParse(observedText)
        : null;
    if (observedText != null && observedAt == null) {
      throw const BridgeFormatException('Invalid profile observation time.');
    }
    if (freshness == AccountProfileFreshness.cached && cachedAt == null) {
      throw const BridgeFormatException('Cached profile requires cachedAtUtc.');
    }
    if (freshness == AccountProfileFreshness.cached &&
        observedAt != null &&
        observedAt != cachedAt) {
      throw const BridgeFormatException(
        'Cached observation must keep its original synchronization time.',
      );
    }
    final email = _optionalString(profile, 'email');
    if (freshness == AccountProfileFreshness.cached && email != null) {
      throw const BridgeFormatException('Cached profile must exclude email.');
    }
    final policy = _requiredMap(payload, 'preferencesPolicy');
    final actions = policy.containsKey('availableActions')
        ? _requiredStringList(policy, 'availableActions')
        : const <String>[];
    final localeOptions = _requiredStringList(policy, 'locales');
    final timeZones = _profileTimeZones(policy['timeZones']);
    final included = policy['directoryIncluded'];
    if (included != null && included is! bool ||
        policy.containsKey('directoryIncluded') && included == null) {
      throw const BridgeFormatException('Invalid directory inclusion flag.');
    }
    final directoryIncluded = included != false;
    if (!directoryIncluded &&
        (!allowDirectoryOmission ||
            freshness != AccountProfileFreshness.live ||
            timeZones.isNotEmpty)) {
      throw const BridgeFormatException(
        'Directory omission requires a live confirmation.',
      );
    }
    return AccountProfilePayload(
      profile: AccountProfile(
        displayName: _optionalString(profile, 'displayName'),
        avatarUrl: _optionalString(profile, 'avatarUrl'),
        email: email,
        locale: _optionalString(profile, 'locale'),
        timeZone: _optionalString(profile, 'timeZone'),
      ),
      freshness: freshness,
      cachedAt: cachedAt,
      observedAt: observedAt,
      localeOptions: localeOptions,
      timeZoneOptions: timeZones,
      directoryIncluded: directoryIncluded,
      supportsPreferenceWrite: actions.contains('profile.patchPreferences'),
      supportsCacheClear: actions.contains('profile.clearLocalCache'),
    );
  }

  static ({List<AccountTimeZoneOption> options, bool allowsWrite})
  profileDirectory(Map<String, Object?> payload) {
    _requireSchema(payload);
    final options = _profileTimeZones(payload['timeZones']);
    if (options.isEmpty) {
      throw const BridgeFormatException('Empty profile directory.');
    }
    return (
      options: options,
      allowsWrite: _requiredStringList(
        payload,
        'availableActions',
      ).contains('profile.patchPreferences'),
    );
  }

  static String? displayCallSign(Object? value) =>
      value is String &&
          value.isNotEmpty &&
          value.length <= 32 &&
          value == value.trim() &&
          !RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value)
      ? value
      : null;

  static List<AccountTimeZoneOption> _profileTimeZones(Object? rawTimeZones) {
    if (rawTimeZones is! List) {
      throw const BridgeFormatException('timeZones must be a list.');
    }
    return rawTimeZones
        .map((item) {
          if (item is! Map) {
            throw const BridgeFormatException(
              'Time-zone directory item must be an object.',
            );
          }
          final entry = item.cast<String, Object?>();
          return AccountTimeZoneOption(
            value: _requiredString(entry, 'value'),
            label: _requiredString(entry, 'label'),
            offset: _requiredString(entry, 'offset'),
          );
        })
        .toList(growable: false);
  }

  static AccountIdentityProjection identity(Map<String, Object?> payload) {
    _requireSchema(payload);
    final state = switch (_requiredString(payload, 'state')) {
      'match' => AccountIdentityState.match,
      'mismatch' => AccountIdentityState.mismatch,
      'awaitingGameIdentity' => AccountIdentityState.awaitingGameIdentity,
      'verificationRequired' => AccountIdentityState.verificationRequired,
      'verificationPending' => AccountIdentityState.verificationPending,
      'reverifyRequired' => AccountIdentityState.reverifyRequired,
      'revoked' => AccountIdentityState.revoked,
      'unknown' => AccountIdentityState.unknown,
      _ => throw const BridgeFormatException(
        'Game identity state is unsupported.',
      ),
    };
    final sensitiveWritesAllowed = payload['sensitiveWritesAllowed'];
    if (sensitiveWritesAllowed is! bool ||
        (sensitiveWritesAllowed && state != AccountIdentityState.match)) {
      throw const BridgeFormatException(
        'Sensitive-write policy contradicts identity state.',
      );
    }
    return AccountIdentityProjection(
      state: state,
      sensitiveWritesAllowed: sensitiveWritesAllowed,
      authoritativeHandle: _optionalString(payload, 'authoritativeHandle'),
      detectedHandle: _optionalString(payload, 'detectedHandle'),
      scmBindingState: switch (payload['scmBindingState']) {
        'bound' => AccountScmBindingState.bound,
        null || 'unknown' => AccountScmBindingState.unknown,
        _ => throw const BridgeFormatException(
          'Unknown account binding state.',
        ),
      },
    );
  }
}

final class AccountProfilePayload {
  const AccountProfilePayload({
    required this.profile,
    required this.freshness,
    required this.cachedAt,
    required this.localeOptions,
    required this.timeZoneOptions,
    required this.supportsPreferenceWrite,
    required this.supportsCacheClear,
    this.observedAt,
    this.directoryIncluded = true,
  });

  final AccountProfile profile;
  final AccountProfileFreshness freshness;
  final DateTime? cachedAt;
  final DateTime? observedAt;
  final List<String> localeOptions;
  final List<AccountTimeZoneOption> timeZoneOptions;
  final bool supportsPreferenceWrite;
  final bool supportsCacheClear;
  final bool directoryIncluded;
}

void _requireSchema(Map<String, Object?> payload) {
  if (payload['schemaVersion'] != 1) {
    throw const BridgeFormatException(
      'Account payload schema version is incompatible.',
    );
  }
}

String _requiredString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! String || value.trim().isEmpty) {
    throw BridgeFormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw BridgeFormatException('$key must be a string or null.');
  }
  return value.trim().isEmpty ? null : value.trim();
}

Map<String, Object?> _requiredMap(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  throw BridgeFormatException('$key must be an object.');
}

List<String> _requiredStringList(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw BridgeFormatException('$key must be a string list.');
  }
  return List.unmodifiable(value.cast<String>());
}

AccountSessionState _parseSessionState(String state) => switch (state) {
  'signedOut' => AccountSessionState.signedOut,
  'credentialTemporarilyUnavailable' =>
    AccountSessionState.credentialTemporarilyUnavailable,
  'signedIn' => AccountSessionState.signedIn,
  'legacySignedIn' => AccountSessionState.legacySignedIn,
  'legacyUnavailable' => AccountSessionState.legacyUnavailable,
  'reauthorizationRequired' => AccountSessionState.reauthorizationRequired,
  _ => throw const BridgeFormatException('Account state is unsupported.'),
};
