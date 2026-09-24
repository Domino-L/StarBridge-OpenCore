import 'personal_profile_models.dart';
import 'personal_profile_port.dart';

final class InMemoryPersonalProfileAdapter implements PersonalProfilePort {
  InMemoryPersonalProfileAdapter({required PersonalProfileSnapshot initial})
    : _snapshot = initial;

  factory InMemoryPersonalProfileAdapter.forReview({required bool signedIn}) {
    if (!signedIn) {
      return InMemoryPersonalProfileAdapter(
        initial: const PersonalProfileSnapshot.signedOut(),
      );
    }
    return InMemoryPersonalProfileAdapter(
      initial: const PersonalProfileSnapshot.available(
        callSign: 'Aster Lin',
        gameHandle: 'Aster-Lin',
        about: '偏爱远征、运输与多人协作。通常在 Stanton 活动。',
        avatarStyle: 0,
        wallpaperId: 'none',
        visibility: PersonalProfileVisibility.everyone,
        presenceIntent: PersonalProfilePresenceIntent.availableSupport,
        affiliations: [
          PersonalProfileAffiliationSummary(
            kind: PersonalProfileAffiliationKind.officialFleet,
            name: "Aster's Wing",
            code: 'ASTER',
            positionLabelKey: 'profile.affiliation.position.fleetMember',
          ),
          PersonalProfileAffiliationSummary(
            kind: PersonalProfileAffiliationKind.featuredCommunity,
            name: 'Northwind 联合社区',
            code: 'NORTH',
            positionLabelKey: 'profile.affiliation.position.operationHost',
          ),
        ],
        availabilityWindows: [
          PersonalProfileAvailabilityWindow(
            dayGroup: PersonalProfileDayGroup.weekdays,
            startTime: '19:30',
            endTime: '23:00',
          ),
          PersonalProfileAvailabilityWindow(
            dayGroup: PersonalProfileDayGroup.weekend,
            startTime: '08:00',
            endTime: '22:00',
          ),
        ],
        timeZoneLabel: 'UTC+08:00',
        gameplayMinutes: 559 * 60 + 8,
        activityRhythm: PersonalProfileActivityRhythm.casual,
        roles: [
          PersonalProfileTagValue(
            labelKey: 'profile.role.expeditionCommander',
            category: PersonalProfileTagCategory.command,
            isPrimary: true,
          ),
          PersonalProfileTagValue(
            labelKey: 'profile.role.pilot',
            category: PersonalProfileTagCategory.ship,
          ),
          PersonalProfileTagValue(
            labelKey: 'profile.role.gunner',
            category: PersonalProfileTagCategory.ship,
          ),
          PersonalProfileTagValue(
            labelKey: 'profile.role.fighterPilot',
            category: PersonalProfileTagCategory.airCombat,
          ),
        ],
        participationInterests: [
          PersonalProfileTagValue(
            labelKey: 'profile.playstyle.pveCombat',
            category: PersonalProfileTagCategory.groundCombat,
          ),
        ],
        supportCapabilities: [
          PersonalProfileTagValue(
            labelKey: 'profile.support.pilot',
            category: PersonalProfileTagCategory.logistics,
          ),
          PersonalProfileTagValue(
            labelKey: 'profile.support.gunner',
            category: PersonalProfileTagCategory.airCombat,
          ),
        ],
        shipWishlist: [],
        favoriteShips: [
          PersonalProfileShipSummary(
            identity: PersonalProfileShipIdentity(
              runtimeId: 'ANVL_Carrack',
              englishName: 'Carrack',
              simplifiedChineseName: '克拉克',
              traditionalChineseName: '克拉克',
            ),
            manufacturer: 'Anvil Aerospace',
            imageAsset: 'assets/ships/carrack.png',
            roleKey: 'profile.shipRole.expedition',
            crewLabel: '3–6',
            sizeKey: 'profile.shipSize.large',
            valueLabel: r'$1,900',
          ),
          PersonalProfileShipSummary(
            identity: PersonalProfileShipIdentity(
              runtimeId: 'DRAK_Vulture',
              englishName: 'Vulture',
              simplifiedChineseName: '秃鹫',
              traditionalChineseName: '禿鷲',
            ),
            manufacturer: 'Drake Interplanetary',
            imageAsset: 'assets/ships/vulture.jpg',
            roleKey: 'profile.shipRole.salvage',
            crewLabel: '1',
            sizeKey: 'profile.shipSize.small',
            valueLabel: r'$300',
          ),
          PersonalProfileShipSummary(
            identity: PersonalProfileShipIdentity(
              runtimeId: 'RSI_Zeus_MR',
              englishName: 'Zeus MR',
              simplifiedChineseName: '宙斯 Mk II MR',
              traditionalChineseName: '宙斯 Mk II MR',
            ),
            manufacturer: 'Roberts Space Industries',
            imageAsset: 'assets/ships/zeus-mk-ii-mr.jpg',
            roleKey: 'profile.shipRole.multirole',
            crewLabel: '1–3',
            sizeKey: 'profile.shipSize.medium',
            valueLabel: r'$650',
          ),
        ],
        hangarSummary: PersonalProfileHangarSummary(
          shipCount: 6,
          manufacturerCount: 4,
          primaryRoleKey: 'profile.shipRole.expedition',
          estimatedValueLabel: r'$3,175',
          categories: [
            PersonalProfileHangarCategorySlice(
              labelKey: 'profile.hangar.category.combat',
              count: 4,
              category: PersonalProfileTagCategory.airCombat,
            ),
            PersonalProfileHangarCategorySlice(
              labelKey: 'profile.hangar.category.other',
              count: 2,
              category: PersonalProfileTagCategory.logistics,
            ),
          ],
          recentlyAddedShip: PersonalProfileShipIdentity(
            runtimeId: 'ANVL_Hornet_F7CM_Mk2',
            englishName: 'Hornet F7CM Mk2',
            simplifiedChineseName: 'F7C-M 超级大黄蜂 MK II',
            traditionalChineseName: 'F7C-M 超級大黃蜂 MK II',
          ),
          recentlyAddedShipImageAsset:
              'assets/ships/f7c-m-super-hornet-mk-ii.jpg',
          recentlyAddedAtLabel: '2026-08-26',
          sourceLabelKey: 'profile.hangar.source.rsiSync',
          syncedAtLabel: '2026-08-31 22:34',
        ),
        moduleLayout: [
          PersonalProfileModuleLayoutItem(
            moduleId: PersonalProfileModuleIds.favoriteShips,
            size: PersonalProfileModuleSize.three,
            isVisible: true,
            position: 0,
          ),
          PersonalProfileModuleLayoutItem(
            moduleId: PersonalProfileModuleIds.hangarSummary,
            size: PersonalProfileModuleSize.three,
            isVisible: true,
            position: 3,
          ),
          PersonalProfileModuleLayoutItem(
            moduleId: PersonalProfileModuleIds.skilledRoles,
            size: PersonalProfileModuleSize.two,
            isVisible: true,
            position: 6,
          ),
        ],
      ),
    );
  }

  @override
  Stream<void> get invalidations => const Stream<void>.empty();

  PersonalProfileSnapshot _snapshot;
  bool _closed = false;

  @override
  Future<PersonalProfileSnapshot> read() async => _snapshot;

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async {
    if (_closed ||
        _snapshot.availability != PersonalProfileAvailability.available ||
        !_snapshot.allowEditing) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    _snapshot = PersonalProfileSnapshot.available(
      callSign: edit.callSign.trim(),
      gameHandle: _snapshot.gameHandle,
      about: edit.about.trim(),
      avatarStyle: edit.avatarStyle,
      wallpaperId: edit.wallpaperId,
      visibility: edit.visibility,
      presenceIntent: _snapshot.presenceIntent,
      affiliations: _snapshot.affiliations,
      availabilityWindows: _snapshot.availabilityWindows,
      timeZoneLabel: _snapshot.timeZoneLabel,
      gameplayMinutes: _snapshot.gameplayMinutes,
      activityRhythm: _snapshot.activityRhythm,
      roles: _snapshot.roles,
      participationInterests: _snapshot.participationInterests,
      supportCapabilities: _snapshot.supportCapabilities,
      shipWishlist: _snapshot.shipWishlist,
      favoriteShips: _snapshot.favoriteShips,
      hangarSummary: _snapshot.hangarSummary,
      moduleLayout: List.unmodifiable(edit.moduleLayout),
    );
    return const PersonalProfileActionResult(
      PersonalProfileActionOutcome.completed,
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
