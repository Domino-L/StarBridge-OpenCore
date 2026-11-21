import 'package:flutter/foundation.dart';

enum AchievementSource { bridge, scm }

enum AchievementRarity { common, rare, epic, legendary }

@immutable
final class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.nameKey,
    required this.conditionKey,
    required this.memoryKey,
    required this.earnedAsset,
    required this.lockedAsset,
    this.earnedDetailAsset,
    this.lockedDetailAsset,
    this.earnedTierAssets = const [],
    this.earnedTierDetailAssets = const [],
    this.thresholds = const [],
    this.groupId = 'journey',
    this.groupNameKey = 'achievements.group.journey',
    this.source = AchievementSource.bridge,
    this.rarity,
    this.hidden = false,
    this.hiddenLockedAsset,
    this.unitKey,
    this.metricKey,
    this.target,
    this.ended = false,
    this.serverName,
    this.serverCondition,
    this.serverMemory,
    this.remoteImageUrl,
    this.conditionParameters = const {},
    this.noteKey,
  });

  final String id;
  final String nameKey;
  final String conditionKey;
  final String memoryKey;
  final String earnedAsset;
  final String lockedAsset;

  /// 大图（512 像素）：详情页或高 DPI 下物理尺寸超过 192 像素时用；
  /// 没有就一直用 [earnedAsset] / [lockedAsset]。
  final String? earnedDetailAsset, lockedDetailAsset;

  /// Optional rank I–V artwork; locked artwork is shared by all ranks.
  final List<String> earnedTierAssets, earnedTierDetailAssets;

  /// 按实际物理边长选图：小于等于 192 像素用列表图，否则用大图。
  String artAsset({
    required bool earned,
    required double logicalSize,
    required double devicePixelRatio,
    int? rank,
  }) {
    final tier = (rank ?? 1).clamp(1, 5) - 1;
    final tiered = earned && isSeries && earnedTierAssets.isNotEmpty;
    final detail = tiered
        ? (earnedTierDetailAssets.isEmpty ? null : earnedTierDetailAssets[tier])
        : earned
        ? earnedDetailAsset
        : lockedDetailAsset;
    final list = tiered
        ? earnedTierAssets[tier]
        : earned
        ? earnedAsset
        : lockedAsset;
    return detail == null || logicalSize * devicePixelRatio <= 192
        ? list
        : detail;
  }

  final List<int> thresholds;
  final String groupId, groupNameKey;
  final AchievementSource source;
  final AchievementRarity? rarity;
  final bool hidden, ended;
  final String? hiddenLockedAsset, unitKey, metricKey;
  final num? target;
  final String? serverName, serverCondition, serverMemory, remoteImageUrl;
  final Map<String, String> conditionParameters;
  final String? noteKey;
  bool get isSeries => thresholds.isNotEmpty;
  static String roman(int rank) =>
      const ['', 'I', 'II', 'III', 'IV', 'V'][rank];
  String rankedName(String name, int rank) =>
      isSeries ? '$name · ${roman(rank.clamp(1, 5))}' : name;
  String condition(String template, int rank) => template.replaceAll(
    '{count}',
    '${thresholds[(rank - 1).clamp(0, thresholds.length - 1)]}',
  );
}

// Catalog order is independent of selection. Future additions belong here;
// opening an inspector must never insert content into either collection list.
const achievementCatalog = <AchievementDefinition>[
  AchievementDefinition(
    id: 'first-entry',
    nameKey: 'achievements.firstEntry.name',
    conditionKey: 'achievements.firstEntry.condition',
    memoryKey: 'achievements.firstEntry.memory',
    earnedAsset: 'assets/achievements/first-entry-earned.png',
    lockedAsset: 'assets/achievements/first-entry-locked.png',
  ),
  // First occurrence determines group order: Journey, Contracts, then Hangar.
  // New journey and TSG art (11-05 paired delivery) has its own earned and locked sets;
  // contract-first uses the 11-05 voucher art, confirmed final by the user on 11-07.
  AchievementDefinition(
    id: 'contract-first',
    groupId: 'contract',
    groupNameKey: 'achievements.group.contract',
    nameKey: 'achievements.contractFirst.name',
    conditionKey: 'achievements.contractFirst.condition',
    memoryKey: 'achievements.contractFirst.memory',
    earnedAsset: 'assets/achievements/contract-first-earned-192.webp',
    earnedDetailAsset: 'assets/achievements/contract-first-earned-512.webp',
    lockedAsset: 'assets/achievements/contract-first-locked-192.webp',
    lockedDetailAsset: 'assets/achievements/contract-first-locked-512.webp',
  ),
  AchievementDefinition(
    id: 'contract-tsg-lead',
    groupId: 'contract',
    groupNameKey: 'achievements.group.contract',
    nameKey: 'achievements.contractTsgLead.name',
    conditionKey: 'achievements.contractTsgLead.condition',
    memoryKey: 'achievements.contractTsgLead.memory',
    earnedAsset: 'assets/achievements/contract-tsg-lead-earned-192.webp',
    earnedDetailAsset: 'assets/achievements/contract-tsg-lead-earned-512.webp',
    lockedAsset: 'assets/achievements/contract-tsg-lead-locked-192.webp',
    lockedDetailAsset: 'assets/achievements/contract-tsg-lead-locked-512.webp',
  ),
  AchievementDefinition(
    id: 'contract-tsg-complete',
    groupId: 'contract',
    groupNameKey: 'achievements.group.contract',
    nameKey: 'achievements.contractTsgComplete.name',
    conditionKey: 'achievements.contractTsgComplete.condition',
    memoryKey: 'achievements.contractTsgComplete.memory',
    earnedAsset: 'assets/achievements/contract-tsg-complete-earned-192.webp',
    earnedDetailAsset:
        'assets/achievements/contract-tsg-complete-earned-512.webp',
    lockedAsset: 'assets/achievements/contract-tsg-complete-locked-192.webp',
    lockedDetailAsset:
        'assets/achievements/contract-tsg-complete-locked-512.webp',
  ),
  AchievementDefinition(
    id: 'contract-tsg-swift',
    groupId: 'contract',
    groupNameKey: 'achievements.group.contract',
    nameKey: 'achievements.contractTsgSwift.name',
    conditionKey: 'achievements.contractTsgSwift.condition',
    memoryKey: 'achievements.contractTsgSwift.memory',
    earnedAsset: 'assets/achievements/contract-tsg-swift-earned-192.webp',
    earnedDetailAsset: 'assets/achievements/contract-tsg-swift-earned-512.webp',
    lockedAsset: 'assets/achievements/contract-tsg-swift-locked-192.webp',
    lockedDetailAsset: 'assets/achievements/contract-tsg-swift-locked-512.webp',
    // TODO: Confirm the time limit with the user and align with the server constant.
    conditionParameters: {'minutes': '90'},
    noteKey: 'achievements.contractTsgSwift.note',
  ),
  AchievementDefinition(
    id: 'contract-tsg-deathless',
    groupId: 'contract',
    groupNameKey: 'achievements.group.contract',
    nameKey: 'achievements.contractTsgDeathless.name',
    conditionKey: 'achievements.contractTsgDeathless.condition',
    memoryKey: 'achievements.contractTsgDeathless.memory',
    earnedAsset: 'assets/achievements/contract-tsg-deathless-earned-192.webp',
    earnedDetailAsset:
        'assets/achievements/contract-tsg-deathless-earned-512.webp',
    lockedAsset: 'assets/achievements/contract-tsg-deathless-locked-192.webp',
    lockedDetailAsset:
        'assets/achievements/contract-tsg-deathless-locked-512.webp',
  ),
  AchievementDefinition(
    id: 'hangar-home',
    groupId: 'hangar',
    groupNameKey: 'achievements.group.hangar',
    unitKey: 'achievements.unit.ships',
    metricKey: 'achievements.metric.ships',
    nameKey: 'achievements.home.name',
    conditionKey: 'achievements.home.condition',
    memoryKey: 'achievements.home.memory',
    earnedAsset: 'assets/achievements/home-1-192.webp',
    earnedDetailAsset: 'assets/achievements/home-1-512.webp',
    lockedAsset: 'assets/achievements/home-locked-192.webp',
    lockedDetailAsset: 'assets/achievements/home-locked-512.webp',
    earnedTierAssets: [
      'assets/achievements/home-1-192.webp',
      'assets/achievements/home-2-192.webp',
      'assets/achievements/home-3-192.webp',
      'assets/achievements/home-4-192.webp',
      'assets/achievements/home-5-192.webp',
    ],
    earnedTierDetailAssets: [
      'assets/achievements/home-1-512.webp',
      'assets/achievements/home-2-512.webp',
      'assets/achievements/home-3-512.webp',
      'assets/achievements/home-4-512.webp',
      'assets/achievements/home-5-512.webp',
    ],
    thresholds: [1, 3, 5, 10, 20],
  ),
  AchievementDefinition(
    id: 'hangar-collection',
    groupId: 'hangar',
    groupNameKey: 'achievements.group.hangar',
    unitKey: 'achievements.unit.models',
    metricKey: 'achievements.metric.models',
    nameKey: 'achievements.collection.name',
    conditionKey: 'achievements.collection.condition',
    memoryKey: 'achievements.collection.memory',
    earnedAsset: 'assets/achievements/collection-1-192.webp',
    earnedDetailAsset: 'assets/achievements/collection-1-512.webp',
    lockedAsset: 'assets/achievements/collection-locked-192.webp',
    lockedDetailAsset: 'assets/achievements/collection-locked-512.webp',
    earnedTierAssets: [
      'assets/achievements/collection-1-192.webp',
      'assets/achievements/collection-2-192.webp',
      'assets/achievements/collection-3-192.webp',
      'assets/achievements/collection-4-192.webp',
      'assets/achievements/collection-5-192.webp',
    ],
    earnedTierDetailAssets: [
      'assets/achievements/collection-1-512.webp',
      'assets/achievements/collection-2-512.webp',
      'assets/achievements/collection-3-512.webp',
      'assets/achievements/collection-4-512.webp',
      'assets/achievements/collection-5-512.webp',
    ],
    thresholds: [3, 5, 8, 12, 20],
  ),
  AchievementDefinition(
    id: 'hangar-paths',
    groupId: 'hangar',
    groupNameKey: 'achievements.group.hangar',
    unitKey: 'achievements.unit.roles',
    metricKey: 'achievements.metric.roles',
    nameKey: 'achievements.paths.name',
    conditionKey: 'achievements.paths.condition',
    memoryKey: 'achievements.paths.memory',
    earnedAsset: 'assets/achievements/paths-1-192.webp',
    earnedDetailAsset: 'assets/achievements/paths-1-512.webp',
    lockedAsset: 'assets/achievements/paths-locked-192.webp',
    lockedDetailAsset: 'assets/achievements/paths-locked-512.webp',
    earnedTierAssets: [
      'assets/achievements/paths-1-192.webp',
      'assets/achievements/paths-2-192.webp',
      'assets/achievements/paths-3-192.webp',
      'assets/achievements/paths-4-192.webp',
      'assets/achievements/paths-5-192.webp',
    ],
    earnedTierDetailAssets: [
      'assets/achievements/paths-1-512.webp',
      'assets/achievements/paths-2-512.webp',
      'assets/achievements/paths-3-512.webp',
      'assets/achievements/paths-4-512.webp',
      'assets/achievements/paths-5-512.webp',
    ],
    thresholds: [2, 3, 4, 5, 6],
  ),
  // 斯坦顿四城抵达（0.7.3）：Host 只认游戏日志里已确认的当前位置，
  // 由星桥自己的服务器登记；四城齐了服务器再给“巡礼斯坦顿”。
  // 图：用户 10-29 定稿的交付包（StarBridge-Stanton-Journey-Client-v1），
  // 192 列表图 + 512 详情图，未解锁版是独立的中性黑灰文件。
  AchievementDefinition(
    id: 'journey-lorville',
    nameKey: 'achievements.lorville.name',
    conditionKey: 'achievements.lorville.condition',
    memoryKey: 'achievements.lorville.memory',
    earnedAsset: 'assets/achievements/journey-lorville-earned-192.webp',
    lockedAsset: 'assets/achievements/journey-lorville-locked-192.webp',
    earnedDetailAsset: 'assets/achievements/journey-lorville-earned-512.webp',
    lockedDetailAsset: 'assets/achievements/journey-lorville-locked-512.webp',
  ),
  AchievementDefinition(
    id: 'journey-area18',
    nameKey: 'achievements.area18.name',
    conditionKey: 'achievements.area18.condition',
    memoryKey: 'achievements.area18.memory',
    earnedAsset: 'assets/achievements/journey-area18-earned-192.webp',
    lockedAsset: 'assets/achievements/journey-area18-locked-192.webp',
    earnedDetailAsset: 'assets/achievements/journey-area18-earned-512.webp',
    lockedDetailAsset: 'assets/achievements/journey-area18-locked-512.webp',
  ),
  AchievementDefinition(
    id: 'journey-orison',
    nameKey: 'achievements.orison.name',
    conditionKey: 'achievements.orison.condition',
    memoryKey: 'achievements.orison.memory',
    earnedAsset: 'assets/achievements/journey-orison-earned-192.webp',
    lockedAsset: 'assets/achievements/journey-orison-locked-192.webp',
    earnedDetailAsset: 'assets/achievements/journey-orison-earned-512.webp',
    lockedDetailAsset: 'assets/achievements/journey-orison-locked-512.webp',
  ),
  AchievementDefinition(
    id: 'journey-new-babbage',
    nameKey: 'achievements.newBabbage.name',
    conditionKey: 'achievements.newBabbage.condition',
    memoryKey: 'achievements.newBabbage.memory',
    earnedAsset: 'assets/achievements/journey-new-babbage-earned-192.webp',
    lockedAsset: 'assets/achievements/journey-new-babbage-locked-192.webp',
    earnedDetailAsset:
        'assets/achievements/journey-new-babbage-earned-512.webp',
    lockedDetailAsset:
        'assets/achievements/journey-new-babbage-locked-512.webp',
  ),
  AchievementDefinition(
    id: 'journey-stanton',
    unitKey: 'achievements.unit.cities',
    metricKey: 'achievements.metric.cities',
    nameKey: 'achievements.stanton.name',
    conditionKey: 'achievements.stanton.condition',
    memoryKey: 'achievements.stanton.memory',
    earnedAsset: 'assets/achievements/journey-stanton-earned-192.webp',
    lockedAsset: 'assets/achievements/journey-stanton-locked-192.webp',
    earnedDetailAsset: 'assets/achievements/journey-stanton-earned-512.webp',
    lockedDetailAsset: 'assets/achievements/journey-stanton-locked-512.webp',
    target: 4,
  ),
  AchievementDefinition(
    id: 'journey-levski',
    nameKey: 'achievements.levski.name',
    conditionKey: 'achievements.levski.condition',
    memoryKey: 'achievements.levski.memory',
    earnedAsset: 'assets/achievements/journey-levski-earned-192.webp',
    earnedDetailAsset: 'assets/achievements/journey-levski-earned-512.webp',
    lockedAsset: 'assets/achievements/journey-levski-locked-192.webp',
    lockedDetailAsset: 'assets/achievements/journey-levski-locked-512.webp',
  ),
  AchievementDefinition(
    id: 'journey-pyro-majors',
    unitKey: 'achievements.unit.stations',
    metricKey: 'achievements.metric.stations',
    nameKey: 'achievements.pyroMajors.name',
    conditionKey: 'achievements.pyroMajors.condition',
    memoryKey: 'achievements.pyroMajors.memory',
    earnedAsset: 'assets/achievements/journey-pyro-majors-earned-192.webp',
    earnedDetailAsset:
        'assets/achievements/journey-pyro-majors-earned-512.webp',
    lockedAsset: 'assets/achievements/journey-pyro-majors-locked-192.webp',
    lockedDetailAsset:
        'assets/achievements/journey-pyro-majors-locked-512.webp',
    target: 3,
  ),
  AchievementDefinition(
    id: 'journey-pyro-all',
    unitKey: 'achievements.unit.stations',
    metricKey: 'achievements.metric.stations',
    nameKey: 'achievements.pyroAll.name',
    conditionKey: 'achievements.pyroAll.condition',
    memoryKey: 'achievements.pyroAll.memory',
    earnedAsset: 'assets/achievements/journey-pyro-all-earned-192.webp',
    earnedDetailAsset: 'assets/achievements/journey-pyro-all-earned-512.webp',
    lockedAsset: 'assets/achievements/journey-pyro-all-locked-192.webp',
    lockedDetailAsset: 'assets/achievements/journey-pyro-all-locked-512.webp',
    target: 23,
  ),
  AchievementDefinition(
    id: 'journey-grimhex',
    nameKey: 'achievements.grimhex.name',
    conditionKey: 'achievements.grimhex.condition',
    memoryKey: 'achievements.grimhex.memory',
    earnedAsset: 'assets/achievements/journey-grimhex-earned-192.webp',
    earnedDetailAsset: 'assets/achievements/journey-grimhex-earned-512.webp',
    lockedAsset: 'assets/achievements/journey-grimhex-locked-192.webp',
    lockedDetailAsset: 'assets/achievements/journey-grimhex-locked-512.webp',
    groupId: 'journey',
  ),
];
