import 'dart:async';
import 'dart:convert';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'personal_profile_affiliation_wire.dart';
import 'personal_profile_models.dart';
import 'personal_profile_presentation.dart';
import 'personal_profile_public_header.dart';
import 'personal_profile_role_catalog.dart';
import 'personal_profile_port.dart';
import 'profile_read_failure.dart';
import 'profile_read_scope.dart';
import 'profile_edit_lease.dart';
import 'profile_gameplay_observation.dart';
import '../hangar/local_hangar_port.dart';
import '../hangar/legacy_profile_hangar.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'personal_profile_local_projection.dart'
    show projectProfileShip, profileShipCategory;

/// Reads and writes the StarBridge personal-profile contract through the Native
/// Host. The adapter never receives the SCM bearer or backend identity keys.
final class BridgePersonalProfileAdapter
    implements
        PersonalProfilePort,
        PersonalProfilePresentationWriter,
        PersonalProfileContentChanges,
        ProfileReadScopeOwner,
        ProfileReadGenerationOwner,
        ProfileReadAccountAdvanceOwner {
  BridgePersonalProfileAdapter(this._session) {
    _invalidationGeneration = _session.activeGeneration;
    _eventSubscription = _session.events.listen(_onBridgeEvent);
  }

  final BridgeClientSession _session;
  @override
  int get activeReadGeneration => _session.activeGeneration;
  // Profile reads share the Host account queue and may include session restore.
  static const _readTimeout = Duration(seconds: 60);
  final StreamController<void> _invalidations =
      StreamController<void>.broadcast();
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _eventSubscription;
  ProfileEditLease? _editLease;
  late int _invalidationGeneration;
  ProfileReadAccountAdvance? _readAccountAdvance;
  @override
  ProfileReadAccountAdvance? get readAccountAdvance => _readAccountAdvance;
  ProfileReadScope? _readScope;
  @override
  ProfileReadScope? get readScope => _readScope;

  @override
  Stream<void> get invalidations => _invalidations.stream;
  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<PersonalProfileSnapshot> read() async {
    _readScope = null;
    _editLease = null;
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
        timeout: _readTimeout,
      );
      ProfileReadScope.requireSchema(account.payload);
      final state = _requiredString(account.payload, 'state');
      if (account.sessionGeneration != _session.activeGeneration) {
        throw BridgeStaleGenerationException(
          account.sessionGeneration,
          _session.activeGeneration,
        );
      }
      if (state == 'signedOut' || state == 'reauthorizationRequired') {
        return const PersonalProfileSnapshot.signedOut();
      }
      if ((state != 'signedIn' && state != 'legacySignedIn') ||
          account.accountContext == null) {
        throw const BridgeFormatException(
          'Signed-in personal profile requires accountContext.',
        );
      }

      final response = await _session.request(
        'personalProfile.getSelf',
        payload: const {'schemaVersion': 1},
        accountContext: account.accountContext,
        timeout: _readTimeout,
      );
      final profile = _requiredMap(response.payload, 'profile');
      final snapshot = _parseSnapshot(response.payload);
      final scope = ProfileReadScope.fromResponse(
        account,
        response,
        _session.activeGeneration,
      );
      if (state == 'signedIn' && snapshot.allowEditing) {
        _editLease = ProfileEditLease(
          account.accountContext!,
          account.sessionGeneration,
          _nonNegativeInt(profile, 'revision'),
          snapshot.presentation,
        );
      }
      _readScope =
          snapshot.availability == PersonalProfileAvailability.available
          ? scope
          : null;
      return snapshot;
    } on Object catch (error) {
      return PersonalProfileSnapshot.unavailable(
        failureKey: profileReadFailureKey(error),
        transientReadFailure: profileReadIsTransient(error),
      );
    }
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async {
    final lease = _editLease;
    if (lease == null) return _refreshBeforeSave;
    // Versioned pages must use explicit groups. Never downgrade a new server
    // lease to the legacy whole-page writer.
    if (lease.presentation != null) return _refreshBeforeSave;
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      ProfileReadScope.requireSchema(account.payload);
      if (_requiredString(account.payload, 'state') != 'signedIn' ||
          account.accountContext == null) {
        return const PersonalProfileActionResult(
          PersonalProfileActionOutcome.rejected,
          failureKey: 'profile.error.reauthorizationRequired',
        );
      }
      if (!identical(_editLease, lease) ||
          !lease.matches(account) ||
          _session.activeGeneration != lease.generation) {
        _editLease = null;
        return _refreshBeforeSave;
      }
      final response = await _session.request(
        'personalProfile.updateSelf',
        payload: <String, Object?>{
          'schemaVersion': 1,
          'patch': <String, Object?>{
            'expectedRevision': lease.revision,
            'visibility': edit.visibility.bridgeValue,
            'callSign': edit.callSign.trim(),
            'avatarStyle': edit.avatarStyle,
            'wallpaperId': edit.wallpaperId,
            'introduction': edit.about.trim(),
            'modules': <Object?>[
              for (final module in edit.moduleLayout)
                <String, Object?>{
                  'id': module.moduleId,
                  'span': module.size.span,
                  'isVisible': module.isVisible,
                  'position': module.position,
                },
            ],
          },
        },
        accountContext: account.accountContext,
      );
      ProfileReadScope.requireSchema(response.payload);
      if (!identical(_editLease, lease) ||
          _session.activeGeneration != lease.generation) {
        return _refreshBeforeSave;
      }
      _editLease = ProfileEditLease(
        lease.context,
        lease.generation,
        _nonNegativeInt(_requiredMap(response.payload, 'profile'), 'revision'),
      );
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.completed,
      );
    } on Object catch (error) {
      if (error is BridgeClientException &&
          error.code == 'personal_profile.write_conflict' &&
          identical(_editLease, lease)) {
        _editLease = null;
      }
      return PersonalProfileActionResult(
        PersonalProfileActionOutcome.failed,
        failureKey: profileSaveFailureKey(error),
      );
    }
  }

  @override
  Future<PersonalProfileActionResult> savePresentation(
    PersonalProfilePresentation expected,
    Map<String, Map<String, Object?>> edits,
  ) async {
    final lease = _editLease;
    var attempted = false;
    if (lease == null ||
        !identical(lease.presentation, expected) ||
        !_session.hostCapabilities.contains(
          'personalProfile.presentation.write.v1',
        )) {
      return _refreshBeforeSave;
    }
    try {
      final payload = expected.editRequest(edits);
      if (payload == null) {
        return const PersonalProfileActionResult(
          PersonalProfileActionOutcome.completed,
        );
      }
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      ProfileReadScope.requireSchema(account.payload);
      if (account.payload['state'] != 'signedIn' ||
          !lease.matches(account) ||
          !identical(_editLease, lease) ||
          _session.activeGeneration != lease.generation ||
          !_session.hostCapabilities.contains(
            'personalProfile.presentation.write.v1',
          )) {
        _editLease = null;
        return _refreshBeforeSave;
      }
      attempted = true;
      final response = await _session.request(
        'personalProfile.updatePresentation',
        payload: payload,
        accountContext: lease.context,
        timeout: _readTimeout,
      );
      if (!identical(_editLease, lease) ||
          !lease.matches(response) ||
          _session.activeGeneration != lease.generation) {
        _editLease = null;
        return _refreshBeforeSave;
      }
      final saved = _parseSnapshot(response.payload).presentation;
      if (saved == null ||
          saved.revision != lease.revision + 1 ||
          edits.keys.any((group) => saved.origins[group] != 'custom')) {
        throw const FormatException('Page confirmation');
      }
      // Require a new displayed read before another edit, including uncertain
      // writes. No rebase or automatic replay with a newer revision.
      _editLease = null;
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.completed,
      );
    } on Object catch (error) {
      if (identical(_editLease, lease)) _editLease = null;
      return PersonalProfileActionResult(
        PersonalProfileActionOutcome.failed,
        requiresReload: true,
        failureKey: attempted
            ? profilePageSaveFailureKey(error)
            : profileSaveFailureKey(error),
      );
    }
  }

  void _onBridgeEvent(BridgeEnvelope event) {
    if (event.name == 'account.changed' ||
        event.name == 'bootstrap.invalidated') {
      _readAccountAdvance = ProfileReadAccountAdvance.observe(
        event,
        _invalidationGeneration,
        _session.activeGeneration,
      );
      _invalidationGeneration = _session.activeGeneration;
      _readScope = null;
      _editLease = null;
      _invalidations.add(null);
    } else if (event.name == 'personalProfile.changed') {
      _changes.add(null);
    }
  }

  @override
  Future<void> close() async {
    await _eventSubscription.cancel();
    await _invalidations.close();
    await _changes.close();
  }
}

const _refreshBeforeSave = PersonalProfileActionResult(
  PersonalProfileActionOutcome.rejected,
  requiresReload: true,
  failureKey: 'profile.error.refreshBeforeSave',
);

PersonalProfileSnapshot parsePersonalProfileSnapshot(
  Map<String, Object?> payload,
) => _parseSnapshot(payload);

PersonalProfileSnapshot _parseSnapshot(Map<String, Object?> payload) {
  ProfileReadScope.requireSchema(payload);
  final editable = payload['editable'];
  if (editable is! bool) {
    throw const BridgeFormatException('editable must be a boolean.');
  }
  if (payload['restricted'] == true) {
    if (editable) {
      throw const BridgeFormatException('A restricted profile is read-only.');
    }
    return parseRestrictedProfile(payload, avatar: _validatedInlineImageData);
  }
  final profile = _requiredMap(payload, 'profile');
  final identity = _requiredMap(profile, 'identity');
  final content = _requiredMap(profile, 'content');
  final hangar = _optionalMap(profile, 'hangar');
  final ships = _parseShips(hangar?['ships']);
  final favoriteCodes = _stringList(content, 'favoriteShipCodes');
  final favoriteShips = <PersonalProfileShipSummary>[
    for (final code in favoriteCodes)
      if (_findShip(ships, code) case final ship?) _toShipSummary(ship),
  ];
  final moduleLayout = _parseModules(content['modules']);

  return PersonalProfileSnapshot.available(
    presentation: PersonalProfilePresentation.fromProfile(profile),
    callSign: _requiredString(identity, 'callSign'),
    // Authorized visitor responses may deliberately redact the Handle.
    // Missing, malformed and editable-owner values retain strict validation.
    gameHandle: !editable && identity['gameHandle'] == ''
        ? ''
        : _requiredString(identity, 'gameHandle'),
    about: _optionalString(content, 'introduction') ?? '',
    avatarStyle: _optionalInt(profile, 'avatarStyle') ?? 0,
    avatarImageData: _validatedInlineImageData(
      _optionalString(identity, 'avatarAssetId'),
    ),
    wallpaperId: _optionalString(profile, 'wallpaperId') ?? 'none',
    visibility: _parseVisibility(profile),
    presenceIntent: _parsePresence(_optionalString(content, 'presenceIntent')),
    affiliations: _parseAffiliations(profile),
    affiliationStatus: parseAffiliationStatus(
      profile['fleetAffiliationStatus'],
    ),
    availabilityWindows: _parseAvailability(content),
    timeZoneLabel: _optionalString(content, 'availabilityTimeZoneId') ?? '',
    gameplayMinutes: profileGameplayMinutes(
      _optionalMap(profile, 'gameplayStatistics'),
    ),
    activityRhythm: _parseActivityRhythm(
      _optionalString(content, 'activityRhythm'),
    ),
    roles: _parseTags(_stringList(content, 'skilledRoles')),
    participationInterests: _parseTags(
      _stringList(content, 'participationInterests'),
    ),
    supportCapabilities: _parseTags(
      _stringList(content, 'supportCapabilities'),
    ),
    shipWishlist: _parseTags(_stringList(content, 'shipWishlist')),
    favoriteShips: favoriteShips,
    hangarSummary: _toHangarSummary(
      ships.where((ship) => ship.isInventoryEntry).toList(growable: false),
      isAvailable: hangar?['ships'] is List,
      unresolvedFavoriteCount: favoriteCodes.length - favoriteShips.length,
    ),
    moduleLayout: moduleLayout,
    allowEditing: editable,
  );
}

PersonalProfileVisibility _parseVisibility(Map<String, Object?> profile) {
  final value = _optionalString(profile, 'visibility');
  if (value != null) {
    return PersonalProfileVisibility.fromBridgeValue(value);
  }
  return _requiredBool(profile, 'isPublic')
      ? PersonalProfileVisibility.everyone
      : PersonalProfileVisibility.onlyMe;
}

List<PersonalProfileAffiliationSummary> _parseAffiliations(
  Map<String, Object?> profile,
) {
  final affiliation = _optionalMap(profile, 'fleetAffiliation');
  if (affiliation == null) {
    return const [];
  }
  final name = _optionalString(affiliation, 'fleetName');
  final code = _optionalString(affiliation, 'fleetCode');
  if (name == null || code == null) {
    return const [];
  }
  return [
    PersonalProfileAffiliationSummary(
      kind: affiliation['kind'] == 'community'
          ? PersonalProfileAffiliationKind.featuredCommunity
          : PersonalProfileAffiliationKind.officialFleet,
      name: name,
      code: code,
      positionLabelKey:
          _optionalString(affiliation, 'positionTitle') ??
          'profile.affiliation.position.fleetMember',
      logoUrl: validatedAffiliationLogoUrl(
        _optionalString(affiliation, 'logoUrl'),
      ),
      logoImageData: _validatedAffiliationLogoData(affiliation),
    ),
  ];
}

String? _validatedAffiliationLogoData(Map<String, Object?> affiliation) {
  return _validatedInlineImageData(
    _optionalString(affiliation, 'logoImageData'),
  );
}

String? _validatedInlineImageData(String? value) {
  if (value == null || value.length > 699120) return null;
  const prefixes = <String>[
    'data:image/png;base64,',
    'data:image/jpeg;base64,',
  ];
  String? prefix;
  for (final candidate in prefixes) {
    if (value.startsWith(candidate)) {
      prefix = candidate;
      break;
    }
  }
  if (prefix == null) return null;
  try {
    final bytes = base64Decode(value.substring(prefix.length));
    return bytes.isEmpty || bytes.length > 512 * 1024 ? null : value;
  } on FormatException {
    return null;
  }
}

List<PersonalProfileAvailabilityWindow> _parseAvailability(
  Map<String, Object?> content,
) {
  if (content['showOnlineTime'] != true) {
    return const [];
  }
  final raw = content['availabilityWindows'];
  if (raw is! List) {
    return const [];
  }
  final result = <PersonalProfileAvailabilityWindow>[];
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    final window = item.cast<String, Object?>();
    final days = window['days'];
    final start = _optionalString(window, 'startTime');
    final end = _optionalString(window, 'endTime');
    if (days is! List || start == null || end == null) {
      continue;
    }
    final normalizedDays = days
        .whereType<int>()
        .where((day) => day >= 0 && day <= 6)
        .toSet()
        .toList();
    if (normalizedDays.isNotEmpty) {
      result.add(
        PersonalProfileAvailabilityWindow(
          days: normalizedDays,
          startTime: start,
          endTime: end,
        ),
      );
    }
  }
  return result;
}

List<PersonalProfileTagValue> _parseTags(List<String> values) => [
  for (final value in values)
    PersonalProfileRoleCatalog.resolve(value) ??
        PersonalProfileTagValue(
          labelKey: value,
          displayLabel: value,
          category: _classifyTag(value),
        ),
];

PersonalProfileTagCategory _classifyTag(String value) {
  final normalized = value.toLowerCase();
  if (_containsAny(normalized, const ['指挥', 'command', 'leader'])) {
    return PersonalProfileTagCategory.command;
  }
  if (_containsAny(normalized, const ['医疗', 'medical', 'medic'])) {
    return PersonalProfileTagCategory.medical;
  }
  if (_containsAny(normalized, const ['后勤', '运输', 'logistics', 'cargo'])) {
    return PersonalProfileTagCategory.logistics;
  }
  if (_containsAny(normalized, const ['采矿', '打捞', '工业', 'mining', 'salvage'])) {
    return PersonalProfileTagCategory.industry;
  }
  if (_containsAny(normalized, const ['地面', 'ground', 'fps'])) {
    return PersonalProfileTagCategory.groundCombat;
  }
  if (_containsAny(normalized, const ['侦察', 'recon', 'scout'])) {
    return PersonalProfileTagCategory.recon;
  }
  if (_containsAny(normalized, const ['空战', 'fighter', 'pvp'])) {
    return PersonalProfileTagCategory.airCombat;
  }
  return PersonalProfileTagCategory.ship;
}

bool _containsAny(String value, List<String> candidates) =>
    candidates.any(value.contains);

List<_RelayShip> _parseShips(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return [
    for (final item in raw)
      if (item is Map) _RelayShip.fromMap(item.cast<String, Object?>()),
  ];
}

_RelayShip? _findShip(List<_RelayShip> ships, String code) {
  for (final ship in ships) {
    if (ship.code.toLowerCase() == code.toLowerCase()) {
      return ship;
    }
  }
  return null;
}

PersonalProfileShipSummary _toShipSummary(_RelayShip ship) =>
    ship.presentation != null
    ? projectProfileShip(ship.presentation!)
    : PersonalProfileShipSummary(
        identity: PersonalProfileShipIdentity(
          runtimeId: ship.code,
          englishName: ship.displayName,
          simplifiedChineseName: ship.displayName,
          traditionalChineseName: ship.displayName,
        ),
        manufacturer: '',
        imageAsset: '',
        roleKey: ship.roleCategory,
        crewLabel: '',
        sizeKey: '',
        valueLabel: '',
      );

PersonalProfileHangarSummary _toHangarSummary(
  List<_RelayShip> ships, {
  required bool isAvailable,
  required int unresolvedFavoriteCount,
}) {
  final counts = <String, int>{};
  var knownCents = 0, unpriced = 0;
  for (final ship in ships) {
    final cents = ShipCatalogDisplay.cents(ship.presentation?.priceUsd);
    if (cents == null) {
      unpriced++;
    } else {
      knownCents += cents;
    }
    final role = ship.presentation?.display?.role ?? ship.roleCategory.trim();
    if (role.isNotEmpty) {
      counts.update(role, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  final categories = [
    for (final entry in counts.entries)
      PersonalProfileHangarCategorySlice(
        labelKey: ShipCatalogDisplay.categories.contains(entry.key)
            ? 'profile.local.category.${entry.key}'
            : entry.key,
        count: entry.value,
        category: ShipCatalogDisplay.categories.contains(entry.key)
            ? profileShipCategory(entry.key)
            : _classifyTag(entry.key),
      ),
  ]..sort((first, second) => second.count.compareTo(first.count));
  final datedShips =
      ships
          .where((ship) => ship.importedAt != null && ship.importedAt!.year > 1)
          .toList()
        ..sort(
          (first, second) => second.importedAt!.compareTo(first.importedAt!),
        );
  final recent = datedShips.isEmpty ? null : datedShips.first;
  final latestSync = ships
      .map((ship) => ship.syncedAt)
      .whereType<DateTime>()
      .fold<DateTime?>(
        null,
        (latest, value) =>
            latest == null || value.isAfter(latest) ? value : latest,
      );
  return PersonalProfileHangarSummary(
    isAvailable: isAvailable,
    unresolvedFavoriteCount: unresolvedFavoriteCount,
    shipCount: ships.length,
    manufacturerCount: 0,
    primaryRoleKey: categories.isEmpty ? '' : categories.first.labelKey,
    estimatedValueLabel: ships.isEmpty || unpriced == ships.length
        ? ''
        : '${ShipCatalogDisplay.usd(knownCents)} USD',
    unpricedCount: unpriced,
    categories: categories,
    recentlyAddedShip: recent == null ? null : _toShipSummary(recent).identity,
    recentlyAddedShipImageAsset: recent == null
        ? ''
        : _toShipSummary(recent).imageAsset,
    recentlyAddedAtLabel: _formatDate(recent?.importedAt),
    sourceLabelKey: 'profile.hangar.source.rsiSync',
    syncedAtLabel: _formatDate(latestSync),
  );
}

List<PersonalProfileModuleLayoutItem> _parseModules(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return [
    for (final item in raw)
      if (item is Map) _moduleFromMap(item.cast<String, Object?>()),
  ];
}

PersonalProfileModuleLayoutItem _moduleFromMap(Map<String, Object?> value) {
  final span = (value['span'] as num?)?.toInt() ?? 1;
  return PersonalProfileModuleLayoutItem(
    moduleId: _requiredString(value, 'id'),
    size: switch (span) {
      2 => PersonalProfileModuleSize.two,
      3 => PersonalProfileModuleSize.three,
      _ => PersonalProfileModuleSize.one,
    },
    isVisible: value['isVisible'] == true,
    position: (value['position'] as num?)?.toInt() ?? -1,
    favoriteShipIds: value['favoriteShipIds'] == null
        ? null
        : List.unmodifiable(_stringList(value, 'favoriteShipIds')),
  );
}

PersonalProfilePresenceIntent _parsePresence(String? value) => switch (value) {
  'looking-for-group' => PersonalProfilePresenceIntent.lookingForGroup,
  'available-support' => PersonalProfilePresenceIntent.availableSupport,
  'busy' => PersonalProfilePresenceIntent.busy,
  'do-not-disturb' => PersonalProfilePresenceIntent.doNotDisturb,
  _ => PersonalProfilePresenceIntent.none,
};

PersonalProfileActivityRhythm _parseActivityRhythm(String? value) =>
    switch (value) {
      '高频活跃' => PersonalProfileActivityRhythm.intensive,
      '稳定活跃' => PersonalProfileActivityRhythm.regular,
      '周末为主' => PersonalProfileActivityRhythm.weekends,
      '不固定' => PersonalProfileActivityRhythm.irregular,
      _ => PersonalProfileActivityRhythm.casual,
    };

String _formatDate(DateTime? value) {
  if (value == null || value.year <= 1) {
    return '';
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

Map<String, Object?> _requiredMap(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! Map) {
    throw BridgeFormatException('$key must be an object.');
  }
  return value.cast<String, Object?>();
}

Map<String, Object?>? _optionalMap(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    throw BridgeFormatException('$key must be an object or null.');
  }
  return value.cast<String, Object?>();
}

String _requiredString(Map<String, Object?> source, String key) {
  final value = _optionalString(source, key);
  if (value == null) {
    throw BridgeFormatException('$key must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw BridgeFormatException('$key must be a string or null.');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

bool _requiredBool(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! bool) {
    throw BridgeFormatException('$key must be a boolean.');
  }
  return value;
}

int _nonNegativeInt(Map<String, Object?> source, String key) {
  final value = _optionalInt(source, key);
  if (value == null || value < 0) {
    throw BridgeFormatException('$key must be a non-negative integer.');
  }
  return value;
}

int? _optionalInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value == null) {
    return null;
  }
  if (value is! num || value.toInt() != value) {
    throw BridgeFormatException('$key must be an integer or null.');
  }
  return value.toInt();
}

List<String> _stringList(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

final class _RelayShip {
  const _RelayShip({
    required this.code,
    required this.displayName,
    required this.importedAt,
    required this.syncedAt,
    required this.roleCategory,
    required this.isInventoryEntry,
    this.presentation,
  });

  factory _RelayShip.fromMap(Map<String, Object?> value) {
    final code = _requiredString(value, 'code');
    final p = _optionalMap(value, 'presentation');
    return _RelayShip(
      code: code,
      displayName: _optionalString(value, 'displayName') ?? code,
      importedAt: DateTime.tryParse(_optionalString(value, 'importedAt') ?? ''),
      syncedAt: DateTime.tryParse(_optionalString(value, 'syncedAt') ?? ''),
      roleCategory: _optionalString(value, 'roleCategory') ?? '',
      isInventoryEntry: value['isInventoryEntry'] != false,
      presentation: p == null ? null : profileHangarShip(value, code),
    );
  }

  final String code;
  final String displayName;
  final DateTime? importedAt;
  final DateTime? syncedAt;
  final String roleCategory;
  final bool isInventoryEntry;
  final LocalHangarShip? presentation;
}
