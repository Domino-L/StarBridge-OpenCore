import '../hangar/local_hangar_port.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'personal_profile_models.dart';
import 'personal_profile_collaboration.dart';
import 'personal_profile_favorite_modules.dart';

PersonalProfileSnapshot projectLocalProfile(
  PersonalProfileSnapshot remote,
  Map<String, Object?>? content,
  LocalHangarSnapshot? hangar,
  DateTime? savedAt, {
  String draftDisplayName = '',
  String? accountAvatarImageData,
  bool legacyAccount = false,
  Map<String, String> timeZones = const {},
}) {
  final remoteAvailable =
      remote.availability == PersonalProfileAvailability.available;
  // Earlier S2 builds materialized empty defaults while skipping Relay reads.
  // Recover only those empty defaults in memory; an explicit new save records
  // clear intent. Never rewrite the prior file or replace nonempty local edits.
  if (legacyAccount &&
      remoteAvailable &&
      content != null &&
      content['preserveEmptyFields'] != true) {
    final inheritedFavorites =
        (content['favoriteShipIds'] as List?)?.isEmpty == true &&
        remote.favoriteShips.isNotEmpty;
    content = {
      ...content,
      if ((content['introduction'] as String? ?? '').trim().isEmpty)
        'introduction': remote.about,
      if (inheritedFavorites) 'favoriteShipIds': null,
      if (inheritedFavorites)
        'modules': [
          for (final item in (content['modules'] as List).cast<Map>())
            {
              for (final entry in item.entries)
                if (entry.key != 'favoriteShipIds' ||
                    (entry.value as List?)?.isNotEmpty == true)
                  entry.key: entry.value,
            },
        ],
    };
  }
  final needsCreation = content == null && !remoteAvailable;
  final available = hangar != null && hangar.revision > 0;
  final currentModels =
      hangar?.ships.map((s) => s.modelKey).toSet() ?? <String>{};
  final retainedChoices = [
    if (available)
      for (final ship in hangar.formerShips)
        projectProfileShip(ship)
            .withFormerOwnership(!currentModels.contains(ship.modelKey)),
  ];
  final choices = [
    if (available)
      for (final ship in hangar.ships) projectProfileShip(ship),
    if (available)
      for (final ship in hangar.formerModels)
        projectProfileShip(ship).withFormerOwnership(true),
  ];
  final ids = needsCreation
      ? const <String>[]
      : (content?['favoriteShipIds'] as List?)?.cast<String>();
  final byId = {
    for (final ship in [...retainedChoices, ...choices])
      ship.identity.runtimeId: ship,
  };
  final favorites = ids == null
      ? [
          for (final ship in remote.favoriteShips)
            if (available && !hangar.partial && !hangar.fromLegacyProfile)
              ship.withFormerOwnership(
                !hangar.ships.any(
                  (owned) =>
                      ship.identity.catalogId != null && owned.catalogId != null
                      ? owned.modelKey == LocalHangarShip(
                          id: ship.identity.runtimeId,
                          title: ship.identity.englishName,
                          catalogId: ship.identity.catalogId,
                        ).modelKey
                      : owned.catalogId?.toLowerCase() ==
                          ship.identity.runtimeId.toLowerCase() ||
                      owned.title.trim().toLowerCase() ==
                          ship.identity.englishName.trim().toLowerCase(),
                ),
              )
            else
              ship,
        ]
      : [for (final id in ids) ?byId[id]];
  final unresolved = ids == null
      ? remote.hangarSummary.unresolvedFavoriteCount
      : ids.where((id) => !byId.containsKey(id)).length;
  final counts = <String, int>{};
  var knownCents = 0, unpriced = 0;
  if (available) {
    for (final ship in hangar.ships) {
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
          recentlyAddedShip: null,
          recentlyAddedShipImageAsset: '',
          recentlyAddedAtLabel: '',
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
      : content == null
      ? remote.moduleLayout
      : [
          for (final item in (content['modules'] as List).cast<Map>())
            PersonalProfileModuleLayoutItem(
              moduleId: item['id'] as String,
              size: PersonalProfileModuleSize.values.firstWhere(
                (s) => s.span == item['span'],
              ),
              isVisible: item['isVisible'] as bool,
              position: item['position'] as int,
              favoriteShipIds: (item['favoriteShipIds'] as List?)
                  ?.cast<String>(),
            ),
        ];
  final style = (content?['playStyle'] as Map?)?.cast<String, Object?>();
  final schedule = (content?['schedule'] as Map?)?.cast<String, Object?>();
  return PersonalProfileSnapshot.available(
    callSign:
        content?['callSign'] as String? ??
        (remoteAvailable ? remote.callSign : draftDisplayName),
    about: content?['introduction'] as String? ?? remote.about,
    avatarStyle: content?['avatarStyle'] as int? ?? remote.avatarStyle,
    avatarImageData: accountAvatarImageData ?? remote.avatarImageData,
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
    roles: ProfileCollaboration.tags(style?['roles'], 'roles') ?? remote.roles,
    participationInterests:
        ProfileCollaboration.tags(style?['interests'], 'interests') ??
        remote.participationInterests,
    supportCapabilities:
        ProfileCollaboration.tags(style?['support'], 'support') ??
        remote.supportCapabilities,
    shipWishlist: remote.shipWishlist,
    favoriteShips: List.unmodifiable(favorites),
    hangarSummary: summary,
    moduleLayout: ProfileFavoriteModules.materialize(layout, ids),
    allowEditing: !remoteAvailable || remote.allowEditing,
    local: PersonalProfileLocalView(
      choices: List.unmodifiable(choices),
      retainedChoices: List.unmodifiable(retainedChoices),
      favoriteShipIds: ids == null ? null : List.unmodifiable(ids),
      hangarAvailable: available,
      remoteAvailable: remoteAvailable,
      needsCreation: needsCreation,
      savedAt: savedAt,
      partial: hangar?.partial ?? false,
      timeZones: timeZones,
    ),
  );
}

PersonalProfileShipSummary projectProfileShip(
  LocalHangarShip ship,
) => PersonalProfileShipSummary(
  identity: PersonalProfileShipIdentity(
    runtimeId: ship.id,
    catalogId: ship.catalogId,
    englishName: ship.title,
    simplifiedChineseName: ship.cn ?? ship.title,
    traditionalChineseName: ship.tw ?? ship.title,
  ),
  manufacturer: ship.liner ?? '',
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
