import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_controller.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';

AccountProjection achievementTestAccount(
  int generation, {
  bool signedIn = true,
  String? retainedReadId,
}) => AccountProjection(
  sessionState: retainedReadId != null
      ? AccountSessionState.credentialTemporarilyUnavailable
      : signedIn
      ? AccountSessionState.signedIn
      : AccountSessionState.signedOut,
  operation: AccountOperation.none,
  generation: generation,
  profileFreshness: AccountProfileFreshness.live,
  identity: const AccountIdentityProjection.unavailable(),
  compatibility: const AccountCompatibilityProjection.unavailable(),
  localeOptions: const [],
  timeZoneOptions: const [],
  retainedReadId: retainedReadId,
);

class DeferredAchievementPort implements AchievementCollectionPort {
  final requests =
      <({int generation, Completer<AchievementCollection> completion})>[];
  @override
  Future<AchievementCollection> read({required int generation}) {
    final completion = Completer<AchievementCollection>();
    requests.add((generation: generation, completion: completion));
    return completion.future;
  }
}

void main() {
  test(
    'retained selection changes clear awards and reject stale completion',
    () async {
      final account = ValueNotifier(
        achievementTestAccount(1, retainedReadId: 'a'),
      );
      final port = DeferredAchievementPort();
      final controller = AchievementCollectionController(
        account: account,
        port: port,
      );
      addTearDown(controller.dispose);
      addTearDown(account.dispose);
      expect(port.requests, hasLength(1));
      account.value = achievementTestAccount(1, retainedReadId: 'b');
      expect(port.requests, hasLength(2));
      port.requests[0].completion.complete(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          earnedAt: {'first-entry': DateTime.utc(2026, 9, 4)},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.earnedAt, isEmpty);
      account.value = achievementTestAccount(1, signedIn: false);
      port.requests[1].completion.complete(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          earnedAt: {'first-entry': DateTime.utc(2026, 9, 4)},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.status, AchievementCollectionStatus.signedOut);
      expect(controller.value.earnedAt, isEmpty);
    },
  );
  test(
    'account changes clear awards immediately and reject late reads',
    () async {
      final account = ValueNotifier(achievementTestAccount(1));
      final port = DeferredAchievementPort();
      final controller = AchievementCollectionController(
        account: account,
        port: port,
      );
      addTearDown(controller.dispose);
      addTearDown(account.dispose);
      port.requests[0].completion.complete(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          earnedAt: {'first-entry': DateTime.utc(2026, 10, 9)},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.isEarned('first-entry'), isTrue);
      final staleRead = controller.refresh();
      account.value = achievementTestAccount(2);
      expect(controller.value.status, AchievementCollectionStatus.loading);
      expect(controller.value.earnedAt, isEmpty);
      port.requests[1].completion.complete(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
          earnedAt: {'first-entry': DateTime.utc(2026, 10, 9)},
        ),
      );
      await staleRead;
      expect(controller.value.generation, 2);
      expect(controller.value.earnedAt, isEmpty);
      port.requests[2].completion.complete(
        AchievementCollection(
          generation: 2,
          status: AchievementCollectionStatus.ready,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.isReady, isTrue);
      expect(controller.value.earnedAt, isEmpty);
    },
  );

  test('read failure retains confirmed collection and marks synchronization failed', () async {
    final account = ValueNotifier(achievementTestAccount(1));
    final port = DeferredAchievementPort();
    final controller = AchievementCollectionController(
      account: account,
      port: port,
    );
    addTearDown(controller.dispose);
    addTearDown(account.dispose);
    port.requests[0].completion.complete(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
        earnedAt: {'first-entry': DateTime.utc(2026, 10, 9)},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final refresh = controller.refresh();
    port.requests.last.completion.completeError(
      StateError('synthetic read failure'),
    );
    await refresh;
    expect(controller.value.isReady, isTrue);
    expect(controller.value.refreshFailed, isTrue);
    expect(controller.value.isEarned('first-entry'), isTrue);
  });

  test(
    'logout, generation mismatch and disposal reject award results',
    () async {
      final account = ValueNotifier(achievementTestAccount(1));
      final port = DeferredAchievementPort();
      final controller = AchievementCollectionController(
        account: account,
        port: port,
      );
      addTearDown(account.dispose);
      port.requests[0].completion.complete(
        AchievementCollection(
          generation: 99,
          status: AchievementCollectionStatus.ready,
          earnedAt: {'first-entry': DateTime.utc(2026, 10, 9)},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.status, AchievementCollectionStatus.unavailable);
      final refresh = controller.refresh();
      account.value = achievementTestAccount(2, signedIn: false);
      expect(controller.value.status, AchievementCollectionStatus.signedOut);
      expect(controller.value.earnedAt, isEmpty);
      controller.dispose();
      port.requests[1].completion.complete(
        AchievementCollection(
          generation: 1,
          status: AchievementCollectionStatus.ready,
        ),
      );
      await refresh;
    },
  );

  test('overlapping same-scope reads share the current request', () async {
    final account = ValueNotifier(achievementTestAccount(1));
    final port = DeferredAchievementPort();
    final controller = AchievementCollectionController(
      account: account,
      port: port,
    );
    addTearDown(controller.dispose);
    addTearDown(account.dispose);
    final latest = controller.refresh();
    expect(port.requests, hasLength(1));
    port.requests[0].completion.complete(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
      ),
    );
    await latest;
    await Future<void>.delayed(Duration.zero);
    expect(controller.value.isReady, isTrue);
    expect(controller.value.earnedAt, isEmpty);
  });
}
