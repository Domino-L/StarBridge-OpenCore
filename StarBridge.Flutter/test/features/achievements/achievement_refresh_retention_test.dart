import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_controller.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';

import 'achievement_collection_controller_test.dart'
    show achievementTestAccount, DeferredAchievementPort;

void main() {
  test(
    'confirmed permanent awards and peak progress never regress on refresh',
    () async {
      final account = ValueNotifier(achievementTestAccount(1));
      final port = DeferredAchievementPort();
      final controller = AchievementCollectionController(
        account: account,
        port: port,
      );
      addTearDown(controller.dispose);
      addTearDown(account.dispose);
      final earnedAt = DateTime.utc(2026, 9, 4);
      port.requests.single.completion.complete(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          earnedAt: {
            'first-entry': earnedAt,
            'hangar-home-1': earnedAt,
            'hangar-home-2': earnedAt,
          },
          progress: {'hangar-home': 4},
        ),
      );
      await controller.ensureLoaded();
      final refreshing = controller.refresh();
      port.requests.last.completion.complete(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          progress: {'hangar-home': 2},
        ),
      );
      await refreshing;
      expect(controller.value.isEarned('first-entry'), isTrue);
      expect(controller.value.rank('hangar-home'), 2);
      expect(controller.value.progressFor('hangar-home'), 4);
      expect(controller.value.earnedAt['first-entry'], earnedAt);
    },
  );

  test(
    'a same-owner refresh keeps the confirmed awards while the read is pending',
    () async {
      final account = ValueNotifier(achievementTestAccount(1));
      final port = DeferredAchievementPort();
      final controller = AchievementCollectionController(
        account: account,
        port: port,
      );
      addTearDown(controller.dispose);
      addTearDown(account.dispose);
      port.requests.single.completion.complete(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          earnedAt: {'first-entry': DateTime.utc(2026, 9, 4)},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final refreshing = controller.refresh();
      expect(controller.value.isEarned('first-entry'), isTrue);
      expect(controller.value.isReady, isTrue);
      port.requests.last.completion.complete(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          earnedAt: {'first-entry': DateTime.utc(2026, 9, 4)},
        ),
      );
      await refreshing;
    },
  );

  test(
    'an explicit read timeout retains confirmed awards for the same owner',
    () async {
      final account = ValueNotifier(achievementTestAccount(1));
      final port = DeferredAchievementPort();
      final controller = AchievementCollectionController(
        account: account,
        port: port,
      );
      addTearDown(controller.dispose);
      addTearDown(account.dispose);
      port.requests.single.completion.complete(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          earnedAt: {'first-entry': DateTime.utc(2026, 9, 4)},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final refreshing = controller.refresh();
      port.requests.last.completion.completeError(
        TimeoutException('synthetic read timeout'),
      );
      await refreshing;
      expect(controller.value.isEarned('first-entry'), isTrue);
    },
  );
}
