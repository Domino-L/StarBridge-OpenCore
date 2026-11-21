import '../hangar/local_hangar_manufacturers.dart';
import '../hangar/local_hangar_port.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'personal_profile_main_role.dart';
import 'personal_profile_models.dart';
import 'personal_profile_showcases.dart';
import 'personal_profile_collaboration.dart';
import 'personal_profile_favorite_modules.dart';

/// Both layouts on disk predate versioned pages. Read their saved selections
/// before projection can inherit any of the server's module picks.
List<String>? savedProfileFavoriteIds(Map<String, Object?>? content) {
  final flat = (content?['favoriteShipIds'] as List?)?.cast<String>();
  if (flat != null) return flat;
  final ids = [
    for (final module in (content?['modules'] as List? ?? const []).cast<Map>())
      ...?(module['favoriteShipIds'] as List?)?.cast<String>(),
  ];
  return ids.isEmpty ? null : ids;
}

List<PersonalProfileModuleLayoutItem> savedProfileLayout(
  Map<String, Object?> content,
) => PersonalProfileShowcases.merge([
  for (final item in (content['modules'] as List? ?? const []).cast<Map>())
    PersonalProfileModuleLayoutItem(
      moduleId: item['id'] as String,
      size: PersonalProfileModuleSize.values.firstWhere(
        (size) => size.span == item['span'],
      ),
      isVisible: item['isVisible'] as bool,
      position: item['position'] as int,
      favoriteShipIds: (item['favoriteShipIds'] as List?)?.cast<String>(),
    ),
], PersonalProfileShowcases.parse(content['showcases']));

PersonalProfileSnapshot projectLocalProfile(
  PersonalProfileSnapshot remote,
  Map<String, Object?>? content,
  LocalHangarSnapshot? hangar,
  DateTime? savedAt, {
  String draftDisplayName = '',
  String? accountAvatarImageData,
  bool legacyAccount = false,
  bool accountCallSign = false,
  Map<String, String> timeZones = const {},
  bool readOnly = false,
  Set<String> preferLocalGroups = const {},
  bool autoImportPending = false,
}) {
  final remoteAvailable =
      remote.availability == PersonalProfileAvailability.available;
  bool preferLocal(String group) =>
      preferLocalGroups.contains(group) &&
      remote.presentation?.canAutoImport(group) == true;
  bool authoritative(String group) =>
      !legacyAccount &&
      remoteAvailable &&
      remote.presentation != null &&
      remote.presentation!.origins[group] != 'unknown' &&
      !preferLocal(group);
  final localFavoriteIds = preferLocal('favorites')
      ? savedProfileFavoriteIds(content)
      : null;
  if (!legacyAccount &&
      remoteAvailable &&
      remote.presentation != null &&
      content != null) {
    content = {...content}; // Never rewrite local storage during projection.
    for (final entry in const {
      'introduction': 'introduction',
      'avatarStyle': 'avatarStyle',
      'wallpaper': 'wallpaperId',
      'playStyle': 'playStyle',
      'schedule': 'schedule',
    }.entries) {
      if (authoritative(entry.key)) content.remove(entry.value);
    }
    if (authoritative('playStyle')) content.remove('mainRole');
    if (authoritative('layout')) {
      // The remote layout already holds its showcase list and picks.
      content
        ..remove('showcases')
        ..remove('achievementShowcase');
      content['modules'] = [
        for (final module in remote.moduleLayout)
          {
            'id': module.moduleId,
            'span': module.size.span,
            'isVisible': module.isVisible,
            'position': module.position,
            if (module.favoriteShipIds != null)
              'favoriteShipIds': module.favoriteShipIds,
          },
      ];
      content['favoriteShipIds'] = ProfileFavoriteModules.selections(
        remote.moduleLayout,
      );
    }
  }
  // Retain the S2 display fallback for profiles saved without a Relay read.
  if ((legacyAccount || preferLocalGroups.isNotEmpty) &&
      remoteAvailable &&
      content != null) {
    final importingLayout = preferLocal('layout');
    final inheritedFavorites =
        (content['favoriteShipIds'] as List?)?.isEmpty == true &&
        (!legacyAccount || content['preserveEmptyFields'] != true) &&
        (importingLayout || remote.favoriteShips.isNotEmpty);
    final remotePicks = {
      for (final item in remote.moduleLayout)
        item.moduleId: item.favoriteShipIds,
    };
    content = {
      ...content,
      if (legacyAccount &&
          (content['introduction'] as String? ?? '').trim().isEmpty &&
          content['preserveEmptyFields'] != true)
        'introduction': remote.about,
      if (inheritedFavorites) 'favoriteShipIds': null,
      if (inheritedFavorites || importingLayout)
        'modules': [
          for (final item
              in (content['modules'] as List? ?? const []).cast<Map>())
            {
              for (final entry in item.entries)
                if (entry.key != 'favoriteShipIds' ||
                    (entry.value as List?)?.isNotEmpty == true)
                  entry.key: entry.value,
              if (remotePicks[item['id']] case final picks?
                  when importingLayout &&
                      (item['favoriteShipIds'] as List?)?.isNotEmpty != true)
                'favoriteShipIds': picks,
            },
        ],
    };
  }
  final needsCreation = content == null && !remoteAvailable;
  final available = hangar != null && hangar.revision > 0;
  final retainedChoices = [
    if (available)
      for (final ship in hangar.formerInstances)
        projectProfileShip(ship).withFormerOwnership(true),
  ];
  final choices = [
    if (available)
      for (final ship in hangar.ships) projectProfileShip(ship),
    ...retainedChoices,
  ];
  final ids = needsCreation
      ? const <String>[]
      : (content?['favoriteShipIds'] as List?)?.cast<String>();
  final byId = {
    for (final ship in [...retainedChoices, ...choices])
      ship.identity.runtimeId: ship,
  };
  var favoriteIds = ids;
  if (preferLocal('favorites')) {
    favoriteIds = localFavoriteIds;
    if (favoriteIds?.isEmpty == true) {
      favoriteIds = null;
    }
  } else if (authoritative('favorites')) {
    favoriteIds = null;
  }
  final favorites = favoriteIds == null
      ? _projectRemoteFavorites(remote.favoriteShips, hangar)
      : [for (final id in favoriteIds) ?byId[id]];
  final unresolved = favoriteIds == null
      ? remote.hangarSummary.unresolvedFavoriteCount
      : favoriteIds.where((id) => !byId.containsKey(id)).length;
  final counts = <String, int>{};
  var knownCents = 0, unpriced = 0;
  LocalHangarShip? recent;
  if (available) {
    for (final ship in hangar.ships) {
      // "最近入库" uses the official RSI pledge date of the current inventory
      // (user 11-12), never the client import time or this snapshot's save
      // time. Equal dates retain inventory order; removed ships and ships
      // without an official date are skipped.
      if (ship.acquiredOn case final acquiredOn?) {
        if (recent == null || acquiredOn.isAfter(recent.acquiredOn!)) {
          recent = ship;
        }
      }
      final role = ShipCatalogDisplay.category(
        ship.display?.role ?? ship.category,
      );
      counts.update(role, (n) => n + 1, ifAbsent: () => 1);
      final cents = ShipCatalogDisplay.cents(ship.priceUsd);
      if (cents == null) {
        unpriced++;
      } else {
        knownCents += cents;
      }
    }
  }
  final summary = !available
      ? (remoteAvailable && remote.hangarSummary.isAvailable
            ? remote.hangarSummary
            : PersonalProfileHangarSummary.empty(
                unresolvedFavoriteCount: unresolved,
              ))
      : PersonalProfileHangarSummary(
          shipCount: hangar.ships.length,
          manufacturerCount: hangar.ships
              .map((s) => s.liner)
              .whereType<String>()
              .toSet()
              .length,
          primaryRoleKey: '',
          estimatedValueLabel: unpriced == hangar.ships.length
              ? ''
              : '${ShipCatalogDisplay.usd(knownCents)} USD',
          unpricedCount: unpriced,
          categories: [
            for (final role in ShipCatalogDisplay.categories)
              if ((counts[role] ?? 0) > 0)
                PersonalProfileHangarCategorySlice(
                  labelKey: 'profile.local.category.$role',
                  count: counts[role]!,
                  category: profileShipCategory(role),
                ),
          ],
          recentlyAddedShip: recent == null
              ? null
              : projectProfileShip(recent).identity,
          recentlyAddedShipImageAsset: recent == null
              ? ''
              : projectProfileShip(recent).imageAsset,
          recentlyAddedAtLabel:
              recent?.acquiredOn?.toString().split(' ').first ?? '',
          sourceLabelKey: hangar.partial
              ? 'profile.local.hangarPartial'
              : 'profile.local.hangarSource',
          syncedAtLabel:
              hangar.savedAt?.toLocal().toString().split('.').first ?? '',
          unresolvedFavoriteCount: unresolved,
        );
  final layout = needsCreation
      ? const [
          PersonalProfileModuleLayoutItem(
            moduleId: PersonalProfileModuleIds.favoriteShips,
            size: PersonalProfileModuleSize.three,
            isVisible: true,
            position: 0,
            favoriteShipIds: [],
          ),
          PersonalProfileModuleLayoutItem(
            moduleId: PersonalProfileModuleIds.hangarSummary,
            size: PersonalProfileModuleSize.three,
            isVisible: true,
            position: 3,
          ),
        ]
      : content == null ||
            !const [
              'modules',
              'showcases',
              'achievementShowcase',
            ].any(content.containsKey)
      ? remote.moduleLayout
      : savedProfileLayout(content);
  final style = (content?['playStyle'] as Map?)?.cast<String, Object?>();
  final recoverEmptyStyle =
      preferLocal('playStyle') && content?['preserveEmptyFields'] != true;
  Object? styleTags(String field) =>
      recoverEmptyStyle && (style?[field] as List?)?.isEmpty == true
      ? null
      : style?[field];
  final schedule = (content?['schedule'] as Map?)?.cast<String, Object?>();
  return PersonalProfileSnapshot.available(
    cachedAtUtc: readOnly ? savedAt : null,
    presentation: remoteAvailable ? remote.presentation : null,
    callSign: accountCallSign && remoteAvailable
        ? remote.callSign
        : content?['callSign'] as String? ??
              (remoteAvailable ? remote.callSign : draftDisplayName),
    about: content?['introduction'] as String? ?? remote.about,
    avatarStyle: content?['avatarStyle'] as int? ?? remote.avatarStyle,
    avatarImageData: legacyAccount
        ? accountAvatarImageData ?? remote.avatarImageData
        : remote.avatarImageData ?? accountAvatarImageData,
    wallpaperId: content?['wallpaperId'] as String? ?? remote.wallpaperId,
    gameHandle: remote.gameHandle,
    visibility: remote.visibility,
    presenceIntent: remote.presenceIntent,
    affiliations: remote.affiliations,
    availabilityWindows: schedule == null
        ? remote.availabilityWindows
        : ProfileCollaboration.windows(schedule['windows']),
    timeZoneLabel: schedule?['timeZoneId'] as String? ?? remote.timeZoneLabel,
    gameplayMinutes: remote.gameplayMinutes,
    activityRhythm: schedule == null
        ? remote.activityRhythm
        : PersonalProfileActivityRhythm.values.byName(
            schedule['rhythm'] as String,
          ),
    roles: ProfileMainRole.mark(
      ProfileCollaboration.tags(styleTags('roles'), 'roles') ?? remote.roles,
      recoverEmptyStyle && content?['mainRole'] == ''
          ? null
          : content?['mainRole'],
    ),
    participationInterests:
        ProfileCollaboration.tags(styleTags('interests'), 'interests') ??
        remote.participationInterests,
    supportCapabilities:
        ProfileCollaboration.tags(styleTags('support'), 'support') ??
        remote.supportCapabilities,
    shipWishlist: remote.shipWishlist,
    favoriteShips: List.unmodifiable(
      ProfileFavoriteModules.firstShipOfEachModel(favorites),
    ),
    hangarSummary: summary,
    // Only the HK page holds the 4th showcase ship; the local path keeps 3.
    // Offered once the HK read shows the second HK release (it carries
    // `mainRole`): an older server would refuse the field.
    // The third HK release holds a 4th per favourite module (user 11-06).
    // User 11-07: each model once on the page. Repeats an older client saved
    // are hidden here only; the next layout save drops them.
    moduleLayout: ProfileFavoriteModules.firstOfEachModel(
      !legacyAccount &&
              remoteAvailable &&
              PersonalProfileFavoriteExtra.serverHoldsEach(
                remote.presentation?.content,
              )
          ? PersonalProfileFavoriteExtra.attachEach(
              ProfileFavoriteModules.materialize(layout, ids),
              PersonalProfileFavoriteExtra.eachOf(remote.moduleLayout),
            )
          : PersonalProfileFavoriteExtra.attach(
              ProfileFavoriteModules.materialize(layout, ids),
              !legacyAccount &&
                      remoteAvailable &&
                      PersonalProfileFavoriteExtra.serverHolds(
                        remote.presentation?.content,
                      )
                  ? PersonalProfileFavoriteExtra.of(remote.moduleLayout) ??
                        const []
                  : null,
            ),
      ProfileFavoriteModules.modelsOf([...favorites, ...byId.values]),
    ),
    showcaseData: PersonalProfileShowcaseData(
      achievementShowcase:
          PersonalProfileShowcases.parseAchievements(
            content?['achievementShowcase'],
          ) ??
          remote.showcaseData.achievementShowcase,
      mainRoleEditable: true, // Saved beside the local file (11-05).
      achievementCount: remoteAvailable
          ? remote.showcaseData.achievementCount
          : null,
      favoriteExtrasEach:
          !legacyAccount &&
          remoteAvailable &&
          PersonalProfileFavoriteExtra.serverHoldsEach(
            remote.presentation?.content,
          ),
    ),
    defaultedPage: remote.defaultedPage,
    allowEditing: !readOnly && (!remoteAvailable || remote.allowEditing),
    local: PersonalProfileLocalView(
      choices: List.unmodifiable(choices),
      retainedChoices: List.unmodifiable(retainedChoices),
      favoriteShipIds: ids == null ? null : List.unmodifiable(ids),
      hangarAvailable: available,
      remoteAvailable: remoteAvailable,
      accountCallSign: accountCallSign,
      autoImportPending: autoImportPending,
      showLocalFavoriteShips:
          preferLocal('favorites') &&
          favoriteIds != null &&
          authoritative('layout'),
      localOnlyEdits:
          accountCallSign && remoteAvailable && remote.presentation == null,
      needsCreation: needsCreation,
      savedAt: savedAt,
      partial: hangar?.partial ?? false,
      timeZones: timeZones,
    ),
  );
}

// Keep the null guard outside the loop and behind a call boundary. Dart 3.13.2
// Windows AOT hoisted hangar.ships.length ahead of the former loop-body guard,
// causing a native access violation when the local hangar was unavailable.
@pragma('vm:never-inline')
List<PersonalProfileShipSummary> _projectRemoteFavorites(
  List<PersonalProfileShipSummary> favorites,
  LocalHangarSnapshot? hangar,
) {
  if (hangar == null ||
      hangar.revision <= 0 ||
      hangar.partial ||
      hangar.fromLegacyProfile) {
    return [...favorites];
  }
  return [
    for (final ship in favorites)
      ship.withFormerOwnership(
        !hangar.ships.any(
          (owned) => ship.identity.catalogId != null && owned.catalogId != null
              ? owned.modelKey ==
                    LocalHangarShip(
                      id: ship.identity.runtimeId,
                      title: ship.identity.englishName,
                      catalogId: ship.identity.catalogId,
                    ).modelKey
              : owned.catalogId?.toLowerCase() ==
                        ship.identity.runtimeId.toLowerCase() ||
                    owned.title.trim().toLowerCase() ==
                        ship.identity.englishName.trim().toLowerCase(),
        ),
      ),
  ];
}

PersonalProfileShipSummary projectProfileShip(
  LocalHangarShip ship,
) => PersonalProfileShipSummary(
  identity: PersonalProfileShipIdentity(
    runtimeId: ship.id,
    nickname: ship.nickname,
    catalogId: ship.catalogId,
    englishName: ship.title,
    simplifiedChineseName: ship.cn ?? ship.title,
    traditionalChineseName: ship.tw ?? ship.title,
  ),
  // The hangar's own maker rule (catalog maker, then a liner that names one),
  // so the large favourite card finds the same mark as the hangar wall.
  manufacturer:
      LocalHangarManufacturers.of(ship)?.en ??
      ship.manufacturer ??
      ship.liner ??
      '',
  imageAsset: ShipCatalogDisplay.image(ship.imageAsset) ?? '',
  thumbnailAsset: ShipCatalogDisplay.image(ship.thumbnailAsset) ?? '',
  roleKey:
      'profile.local.category.${ShipCatalogDisplay.category(ship.display?.role ?? ship.category)}',
  catalogIconKey: ship.display?.iconKey,
  crewLabel: '—',
  sizeKey: ship.display != null
      ? 'profile.local.size.${ship.display!.spec}'
      : const ['small', 'medium', 'large', 'capital'].contains(ship.sizeClass)
      ? 'profile.local.size.${ship.sizeClass}'
      : 'profile.local.unknown',
  valueLabel: switch (ShipCatalogDisplay.cents(ship.priceUsd)) {
    final int cents => '${ShipCatalogDisplay.usd(cents)} USD',
    _ => '',
  },
  valueLabelKey: 'profile.local.catalogPrice',
);

PersonalProfileTagCategory profileShipCategory(String role) => switch (role) {
  'ground-combat' => PersonalProfileTagCategory.groundCombat,
  'ground-transport' => PersonalProfileTagCategory.logistics,
  'ground-industrial' => PersonalProfileTagCategory.industry,
  'ground-exploration' => PersonalProfileTagCategory.recon,
  'ground-support' => PersonalProfileTagCategory.medical,
  'combat' => PersonalProfileTagCategory.airCombat,
  'transport' => PersonalProfileTagCategory.logistics,
  'industrial' => PersonalProfileTagCategory.industry,
  'exploration' => PersonalProfileTagCategory.recon,
  'support' => PersonalProfileTagCategory.medical,
  _ => PersonalProfileTagCategory.ship,
};
