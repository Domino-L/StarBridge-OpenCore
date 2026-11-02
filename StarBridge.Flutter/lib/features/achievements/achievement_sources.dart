import 'achievement_catalog.dart';
import 'achievement_collection_port.dart';

/// Presentation only. Each source retains its own replacement/cache policy.
AchievementCollection combineAchievementSources(
  AchievementCollection bridge,
  AchievementCollection? scm,
  List<AchievementDefinition> bridgeCatalog,
) {
  if (scm == null || scm.generation != bridge.generation) return bridge;
  final ready = bridge.isReady || scm.isReady;
  return AchievementCollection(
    generation: bridge.generation,
    status: ready ? AchievementCollectionStatus.ready : bridge.status,
    catalog: [...bridgeCatalog, ...scm.catalog],
    earnedAt: {...bridge.earnedAt, ...scm.earnedAt},
    ownedIds: {...bridge.ownedIds, ...scm.ownedIds},
    unknownIds: {
      if (!bridge.isReady) ...bridgeCatalog.map((d) => d.id),
      if (!scm.isReady) ...scm.catalog.map((d) => d.id),
    },
    progress: bridge.progress == null && scm.progress == null
        ? null
        : {...?bridge.progress, ...?scm.progress},
    cachedAtUtc: bridge.cachedAtUtc ?? scm.cachedAtUtc,
    synchronizedAtUtc: bridge.synchronizedAtUtc ?? scm.synchronizedAtUtc,
    isRefreshing: bridge.isRefreshing || scm.isRefreshing,
    refreshFailed: bridge.refreshFailed || scm.refreshFailed,
  );
}
