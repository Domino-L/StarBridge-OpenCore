import 'dart:convert';

import 'bridge_personal_profile_account_facts.dart' show parseAccountFacts;
import '../../platform/bridge/bridge_envelope.dart';
import 'personal_profile_favorite_modules.dart';
import 'personal_profile_main_role.dart';
import 'personal_profile_affiliation_wire.dart';
import 'personal_profile_showcases.dart';
import 'personal_profile_models.dart';
import 'personal_profile_presentation.dart';
import 'personal_profile_public_header.dart';
import 'personal_profile_wire_tags.dart';
import 'profile_read_scope.dart';
import 'profile_gameplay_observation.dart';
import '../hangar/local_hangar_port.dart';
import '../hangar/legacy_profile_hangar.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'personal_profile_local_projection.dart'
    show projectProfileShip, profileShipCategory;

import 'personal_profile_visitor_favorites.dart';

PersonalProfileSnapshot parsePersonalProfileSnapshot(
  Map<String, Object?> payload, {
  bool visitorAccountFactsSupported = false,
}) {
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
  final profile = requireProfileWireMap(payload, 'profile');
  final identity = requireProfileWireMap(profile, 'identity');
  final content = requireProfileWireMap(profile, 'content');
  final hangar = _optionalMap(profile, 'hangar');
  final ships = _parseShips(hangar?['ships']);
  final modules = _parseModules(content['modules']);
  // Visitors use only visible modules' 4th ships, everywhere below.
  final showcaseContent = editable
      ? content
      : visitorVisibleExtras(content, modules);
  // The 4th showcase ship is looked up like the module favourites.
  final legacyFavoriteCodes = [
    ..._stringList(content, 'favoriteShipCodes'),
    ...?PersonalProfileFavoriteExtra.parse(
      showcaseContent['favoriteShowcaseExtra'],
    ),
    ...?PersonalProfileFavoriteExtra.parseEach(
      showcaseContent['favoriteShowcaseExtras'],
    )?.values,
  ];
  final showcases = readPersonalProfileShowcases(
    // Visitors drop hidden picks before the 4th ships attach, so a hidden pick
    // never reserves a visible ship; the snapshot gets them back below.
    modules: editable ? modules : visitorWithoutHiddenPicks(modules),
    content: showcaseContent,
    profile: profile,
    editable: editable,
  );
  PersonalProfileShipIdentity? lookup(String id) =>
      switch (_findShip(ships, id)) {
        final ship? => _toShipSummary(ship).identity,
        null => null,
      };
  final layout = editable
      ? showcases.layout
      : visitorFlatFavorites(
          visitorFavoriteLayout(showcases.layout),
          _stringList(content, 'favoriteShipCodes'),
          lookup,
        );
  final favoriteCodes = editable
      ? legacyFavoriteCodes
      : visitorFavoriteCodes(layout, legacyFavoriteCodes);
  final favoriteShips = <PersonalProfileShipSummary>[
    for (final code in favoriteCodes)
      if (_findShip(ships, code) case final ship?) _toShipSummary(ship),
  ];
  // User 11-07: each model once on a page (the Host adds each hangar row's
  // catalog ID); layout and ship list keep the same ship of a model.
  final filtered = ProfileFavoriteModules.shownFavorites(
    layout,
    favoriteShips,
    lookup,
  );
  final shown = editable
      ? filtered
      : (
          layout: visitorRestoreHiddenPicks(filtered.layout, modules),
          ships: filtered.ships,
        );

  return PersonalProfileSnapshot.available(
    defaultedPage: editable && profileNeverSaved(profile),
    accountFacts: !editable && visitorAccountFactsSupported
        ? parseAccountFacts(payload['accountFacts'])
        : null,
    publicTradeWindow: editable ? null : parseFullPageTradeWindow(profile),

    presentation: PersonalProfilePresentation.fromProfile(profile),
    callSign: requireProfileWireString(identity, 'callSign'),
    // Authorized visitor responses may deliberately redact the Handle.
    // Missing, malformed and editable-owner values retain strict validation.
    gameHandle: !editable && identity['gameHandle'] == ''
        ? ''
        : requireProfileWireString(identity, 'gameHandle'),
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
    roles: ProfileMainRole.mark(
      parseProfileTags(_stringList(content, 'skilledRoles')),
      content['mainRole'],
    ),
    participationInterests: parseProfileTags(
      _stringList(content, 'participationInterests'),
    ),
    supportCapabilities: parseProfileTags(
      _stringList(content, 'supportCapabilities'),
    ),
    shipWishlist: parseProfileTags(_stringList(content, 'shipWishlist')),
    favoriteShips: shown.ships,
    hangarSummary: _toHangarSummary(
      ships.where((ship) => ship.isInventoryEntry).toList(growable: false),
      isAvailable: hangar?['ships'] is List,
      unresolvedFavoriteCount: favoriteCodes.length - favoriteShips.length,
    ),
    moduleLayout: shown.layout,
    showcaseData: showcases.data,
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
            : classifyProfileTag(entry.key),
      ),
  ]..sort((first, second) => second.count.compareTo(first.count));
  // "最近入库" needs the official RSI pledge date (user 11-12). The synced
  // profile's importedAt may be the 0.7.2 import moment, so this summary
  // shows no recent ship rather than ranking by import time.
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
    recentlyAddedShip: null,
    recentlyAddedShipImageAsset: '',
    recentlyAddedAtLabel: '',
    sourceLabelKey: 'profile.hangar.source.rsiSync',
    syncedAtLabel: _formatDate(latestSync),
  );
}

List<PersonalProfileModuleLayoutItem> _parseModules(Object? raw) => [
  if (raw is List)
    for (final item in raw)
      if (item is Map) _moduleFromMap(item.cast<String, Object?>()),
];

PersonalProfileModuleLayoutItem _moduleFromMap(Map<String, Object?> value) {
  final span = (value['span'] as num?)?.toInt() ?? 1;
  return PersonalProfileModuleLayoutItem(
    moduleId: requireProfileWireString(value, 'id'),
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

Map<String, Object?> requireProfileWireMap(
  Map<String, Object?> source,
  String key,
) {
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

String requireProfileWireString(Map<String, Object?> source, String key) {
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

int requireProfileWireRevision(Map<String, Object?> source, String key) {
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
    required this.syncedAt,
    required this.roleCategory,
    required this.isInventoryEntry,
    this.presentation,
  });

  factory _RelayShip.fromMap(Map<String, Object?> value) {
    final code = requireProfileWireString(value, 'code');
    final p = _optionalMap(value, 'presentation');
    // Still part of the wire contract (validated), but not shown: it may be a
    // 0.7.2 import moment rather than the RSI pledge date (user 11-12).
    _optionalString(value, 'importedAt');
    return _RelayShip(
      code: code,
      displayName: _optionalString(value, 'displayName') ?? code,
      syncedAt: DateTime.tryParse(_optionalString(value, 'syncedAt') ?? ''),
      roleCategory: _optionalString(value, 'roleCategory') ?? '',
      isInventoryEntry: value['isInventoryEntry'] != false,
      presentation: p == null ? null : profileHangarShip(value, code),
    );
  }

  final String code;
  final String displayName;
  final DateTime? syncedAt;
  final String roleCategory;
  final bool isInventoryEntry;
  final LocalHangarShip? presentation;
}
