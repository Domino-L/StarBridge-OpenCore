import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_achievement_sources.dart';

// build 65: the profile header said "0 项成就" while the achievements page said
// 10 / 47. The Host read carries no catalog, so the profile counted nothing.
void main() {
  int earned(AchievementCollection c) =>
      c.catalog.where((d) => c.isEarned(d.id)).length;

  final first = achievementCatalog.first;
  final when = DateTime.utc(2026, 11, 1);
  final scmDefinition = AchievementDefinition(
    id: 'scm-synthetic-1',
    nameKey: 'n',
    conditionKey: 'c',
    memoryKey: 'm',
    earnedAsset: 'a',
    lockedAsset: 'b',
    source: AchievementSource.scm,
  );

  test('the Host read alone is counted against the full catalog', () {
    final bridge = AchievementCollection(
      generation: 3,
      status: AchievementCollectionStatus.ready,
      earnedAt: {first.id: when},
    );
    expect(bridge.catalog, isEmpty, reason: 'what the Host read carries');
    final shown = profileAchievementCollection(bridge, null);
    expect(shown.catalog.length, achievementCatalog.length);
    expect(earned(shown), 1);
  });

  test('SCM achievements are counted like the achievements page', () {
    final bridge = AchievementCollection(
      generation: 3,
      status: AchievementCollectionStatus.ready,
      earnedAt: {first.id: when},
    );
    final scm = AchievementCollection(
      generation: 3,
      status: AchievementCollectionStatus.ready,
      catalog: [scmDefinition],
      earnedAt: {scmDefinition.id: when},
    );
    final shown = profileAchievementCollection(bridge, scm);
    expect(shown.catalog.length, achievementCatalog.length + 1);
    expect(earned(shown), 2);
    // Another account's SCM read is ignored.
    final stale = AchievementCollection(
      generation: 2,
      status: AchievementCollectionStatus.ready,
      catalog: [scmDefinition],
      earnedAt: {scmDefinition.id: when},
    );
    expect(earned(profileAchievementCollection(bridge, stale)), 1);
  });

  test('nothing counts before the Host read is ready', () {
    final loading = AchievementCollection(
      generation: 3,
      status: AchievementCollectionStatus.loading,
    );
    expect(profileAchievementCollection(loading, null).isReady, isFalse);
  });

  test('the shared view follows both collections', () {
    final bridge = ValueNotifier(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
      ),
    );
    final scm = ValueNotifier(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.loading,
      ),
    );
    final sources = ProfileAchievementSources(bridge, scm);
    var notified = 0;
    sources.addListener(() => notified++);
    scm.value = AchievementCollection(
      generation: 1,
      status: AchievementCollectionStatus.ready,
      catalog: [scmDefinition],
      earnedAt: {scmDefinition.id: when},
    );
    expect(notified, 1);
    expect(earned(sources.value), 1);
    sources.dispose();
    bridge.value = bridge.value;
    scm.value = AchievementCollection(
      generation: 1,
      status: AchievementCollectionStatus.loading,
    );
    expect(notified, 1);
  });

  test('while the Host read is not ready the number stays hidden, as on '
      'the achievements page', () {
    final scm = AchievementCollection(
      generation: 3,
      status: AchievementCollectionStatus.ready,
      catalog: [scmDefinition],
      earnedAt: {scmDefinition.id: when},
    );
    final shown = profileAchievementCollection(
      AchievementCollection(
        generation: 3,
        status: AchievementCollectionStatus.loading,
      ),
      scm,
    );
    // The page shows '—' unless ready with nothing unknown; so does the header.
    expect(shown.isReady && shown.unknownIds.isEmpty, isFalse);
  });
}
