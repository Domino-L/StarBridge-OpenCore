import 'package:starbridge_flutter/features/tools/catalog_port.dart';

const missionGuid = '00000000-0000-0000-0000-000000000073';
const missionSample = <String, Object?>{
  'missionGuid': missionGuid,
  'title': 'Sample contract',
  'titleCn': '示意合约',
  'missionType': 'Delivery',
  'missionTypeCn': '运输',
  'issuerName': 'Example issuer',
  'issuerNameCn': '示意发布方',
  'factionName': 'Sample faction',
  'factionNameCn': '示意阵营',
  'isCombatMission': false,
  'difficulty': {'name': 'Standard', 'nameCn': '标准', 'level': 2},
  'minStanding': {'name': 'Trainee', 'rankNameCn': '见习', 'minReputation': 0},
  'maxStanding': {
    'name': 'Experienced',
    'rankNameCn': '熟练',
    'minReputation': 1000,
  },
  'cargoPickupCount': 1,
  'cargoDropoffCount': 2,
  'destinations': [
    {'name': 'Sample destination', 'nameCn': '示意目的地'},
  ],
  'shipEncounters': {
    'possibleShips': [
      {'nameEn': 'Sample ship', 'nameCn': '示意舰船'},
    ],
  },
  'itemRewards': [
    {'nameEn': 'Sample supply', 'nameCn': '示意补给', 'amount': 2},
  ],
  'systems': ['Stanton'],
  'rewardUec': 500,
  'baseXp': 12,
  'blueprintRewardCount': 1,
  'minRankIndex': 1,
  'maxRankIndex': 3,
  'cargoMinScu': 4,
  'cargoMaxScu': 8,
  'canBeShared': true,
  'illegal': false,
  'buyIn': 0,
  'timeToComplete': 600,
  'description': 'Deliver sample cargo.',
  'descriptionCn': '运送示意货物。',
  'locations': [
    {'name': 'Sample outpost', 'nameCn': '示意地点'},
  ],
  'rewardBlueprints': [
    {
      'id': 73,
      'name': 'Sample helmet',
      'nameCn': '示意头盔',
      'categoryName': 'FPSArmours',
      'chance': 0.25,
    },
  ],
};
const blueprintSample = <String, Object?>{
  'id': 73,
  'blueprintName': 'Sample helmet',
  'blueprintNameCn': '示意头盔',
  'categoryName': 'FPSArmours',
  'subcategory': 'helmet',
  'manufacturer': 'armr',
  'itemClass': 'Military',
  'baseStats': {
    'Armor_DamageMitigation': 30,
    'Armor_TemperatureMin': -30,
    'Armor_TemperatureMax': 60,
  },
  'grade': 2,
  'craftTimeSeconds': 270,
  'rewardMissionCount': 1,
  'slots': [
    {
      'slotDisplayName': 'Shell',
      'slotDisplayNameCn': '外壳',
      'requiredCount': 3,
      'options': [
        {
          'materialName': 'Sample alloy',
          'materialNameCn': '示意合金',
          'quantity': 3,
          'minQuality': 500,
        },
      ],
    },
  ],
};

class SampleCatalogPort implements CatalogPort {
  final calls = <({String operation, CatalogRow parameters, bool refresh})>[];
  final opened = <CatalogKind>[];
  final failures = <String, CatalogFailure>{};
  CatalogRow? missionFilters, blueprintFilters;
  List<CatalogRow>? blueprintRows;
  bool empty = false, disposed = false;
  @override
  bool get canOpenWebsite => true;
  @override
  Future<CatalogRow> read(
    String operation,
    CatalogRow parameters, {
    bool refresh = false,
  }) async {
    calls.add((
      operation: operation,
      parameters: {...parameters},
      refresh: refresh,
    ));
    final failure = failures[operation];
    if (failure != null) throw failure;
    return switch (operation) {
      'missions.page' => {
        'rows': empty ? [] : [missionSample],
        'total': empty ? 0 : 21,
      },
      'blueprints.page' => {
        'rows': empty ? [] : blueprintRows ?? [blueprintSample],
        'total': empty ? 0 : 21,
      },
      'missions.filters' =>
        missionFilters ??
            {
              'missionTypes': ['Delivery'],
              'systems': ['Stanton'],
              'missionTypeOptions': [
                {'value': 'Delivery', 'label': 'Delivery', 'labelCn': '运输'},
              ],
              'categories': [
                {
                  'value': 'Delivery',
                  'label': 'Delivery',
                  'labelCn': '运输类',
                  'missionCount': 12,
                },
              ],
              'factions': [
                {
                  'value': 'Sample faction',
                  'label': 'Sample faction',
                  'labelCn': '示意阵营',
                  'missionCount': 8,
                },
              ],
              'issuers': [
                {
                  'value': 'Example issuer',
                  'label': 'Example issuer',
                  'labelCn': '示意发布方',
                  'missionCount': 5,
                },
              ],
            },
      'blueprints.filters' =>
        blueprintFilters ??
            {
              'grades': ['A', 'B'],
              'manufacturers': ['armr'],
              'itemClasses': ['Military'],
              'missionTypes': [
                {'name': 'Delivery', 'nameCn': '运输', 'count': 1},
              ],
            },
      'missions.detail' => {...missionSample},
      // BlueprintDetailRespVO has no top-level manufacturer in this snapshot.
      'blueprints.detail' => {...blueprintSample}..remove('manufacturer'),
      'blueprints.missions' => {
        'rows': [
          {...missionSample, 'rewardChance': 0.25},
        ],
      },
      _ => throw StateError('Unexpected synthetic operation: $operation'),
    };
  }

  @override
  Future<void> openWebsite(CatalogKind kind, CatalogRow detail) async =>
      opened.add(kind);
  @override
  void dispose() {
    disposed = true;
  }
}
