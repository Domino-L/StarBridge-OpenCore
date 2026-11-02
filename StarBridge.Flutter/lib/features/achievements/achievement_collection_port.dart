import 'package:flutter/foundation.dart';

import 'achievement_catalog.dart';

enum AchievementCollectionStatus { signedOut, loading, unavailable, ready }

@immutable
final class AchievementCollection {
  AchievementCollection({
    required this.generation,
    required this.status,
    Map<String, DateTime> earnedAt = const {},
    Map<String, num>? progress,
    List<AchievementDefinition> catalog = const [],
    Set<String> ownedIds = const {},
    Set<String> unknownIds = const {},
    this.cachedAtUtc,
    this.isRefreshing = false,
    this.refreshFailed = false,
    this.synchronizedAtUtc,
    this.transientFailure = false,
  }) : catalog = List.unmodifiable(
         status == AchievementCollectionStatus.ready
             ? catalog
             : const <AchievementDefinition>[],
       ),
       ownedIds = Set.unmodifiable(
         status == AchievementCollectionStatus.ready
             ? ownedIds
             : const <String>{},
       ),
       unknownIds = Set.unmodifiable(unknownIds),
       earnedAt = Map.unmodifiable(
         status == AchievementCollectionStatus.ready
             ? earnedAt
             : const <String, DateTime>{},
       ),
       progress =
           status == AchievementCollectionStatus.ready && progress != null
           ? Map.unmodifiable(progress)
           : null;

  final List<AchievementDefinition> catalog;
  final Set<String> ownedIds, unknownIds;
  bool isConfirmed(String id) => isReady && !unknownIds.contains(id);

  final int generation;
  final AchievementCollectionStatus status;
  final Map<String, DateTime> earnedAt;
  final Map<String, num>? progress;

  /// Present only for a retained server-confirmed, read-only offline snapshot.
  final DateTime? cachedAtUtc;
  final bool isRefreshing;
  final bool refreshFailed;
  final DateTime? synchronizedAtUtc;
  // Set only by an adapter that can distinguish a transport failure from
  // identity, permission, schema and generation failures. Unknown fails closed.
  final bool transientFailure;
  int rank(String id) => !isReady
      ? 0
      : [
          for (var rank = 1; rank <= 5; rank++)
            if (earnedAt.containsKey('$id-$rank')) rank,
        ].fold(0, (a, b) => a > b ? a : b);
  num? progressFor(String id) =>
      isReady && progress != null ? progress![id] : null;
  DateTime? dateFor(String id) =>
      rank(id) > 0 ? earnedAt['$id-${rank(id)}'] : earnedAt[id];

  bool get isReady => status == AchievementCollectionStatus.ready;
  bool isEarned(String id) =>
      isConfirmed(id) &&
      (ownedIds.contains(id) || earnedAt.containsKey(id) || rank(id) > 0);
}

/// Read-only account projection. The owning adapter must read the authenticated
/// account and echo its session generation; Flutter does not own award writes.
abstract interface class AchievementCollectionPort {
  Future<AchievementCollection> read({required int generation});
}

abstract interface class AchievementCollectionInvalidations {
  /// Hard loss of the current read context; old data must disappear immediately.
  Stream<void> get invalidations;
}

abstract interface class AchievementCollectionChanges {
  /// Same-owner content change; mark stale and refresh without removing data.
  Stream<void> get changes;
}

/// A host without the cloud contract remains unavailable, independently of a
/// confirmed empty collection. Demonstration or offline data never grants awards.
final class UnavailableAchievementCollection
    implements AchievementCollectionPort {
  const UnavailableAchievementCollection();

  @override
  Future<AchievementCollection> read({required int generation}) async =>
      AchievementCollection(
        generation: generation,
        status: AchievementCollectionStatus.unavailable,
      );
}
