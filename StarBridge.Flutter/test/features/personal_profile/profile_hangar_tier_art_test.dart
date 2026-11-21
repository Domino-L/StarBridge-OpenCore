import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_achievement_showcase.dart';

void main() {
  test(
    'owner showcase retains the confirmed rank with its selected definition',
    () {
      final when = DateTime.utc(2026, 11, 8);
      final items = profileOwnerAchievements(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          catalog: achievementCatalog,
          earnedAt: {
            'hangar-home-2': when,
            'hangar-home-4': when,
            'hangar-paths-3': when,
          },
        ),
        ['hangar-paths', 'hangar-home'],
      );
      expect(items.map((item) => item.definition.id), [
        'hangar-paths',
        'hangar-home',
      ]);
      expect(items.map((item) => item.rank), [3, 4]);
    },
  );

  test(
    'visitor showcase preserves ranked IDs while resolving base artwork',
    () {
      final snapshot = parsePersonalProfileSnapshot({
        'schemaVersion': 1,
        'editable': false,
        'profile': {
          'isPublic': true,
          'visibility': 'everyone',
          'revision': 1,
          'identity': {
            'callSign': 'Synthetic pilot',
            'gameHandle': 'SyntheticPilot',
          },
          'content': <String, Object?>{},
          'publicAchievements': [
            {'id': 'hangar-home-5', 'earnedAt': '2026-11-08T00:00:00Z'},
            {'id': 'hangar-collection-2', 'earnedAt': '2026-11-08T00:00:00Z'},
            {'id': 'first-entry', 'earnedAt': '2026-11-08T00:00:00Z'},
          ],
        },
      });
      final items = profileVisitorAchievements(
        snapshot.showcaseData.publicAchievements!,
      );
      expect(items.map((item) => item.definition.id), [
        'hangar-home',
        'hangar-collection',
        'first-entry',
      ]);
      expect(items.map((item) => item.rank), [5, 2, 0]);
    },
  );
}
