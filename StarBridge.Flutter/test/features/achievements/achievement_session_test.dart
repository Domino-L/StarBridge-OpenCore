import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_session.dart';

import 'achievement_collection_controller_test.dart'
    show achievementTestAccount, DeferredAchievementPort;

void main() {
  late _ObservedAccount account;
  late _NotifyingPort port;
  late AchievementCollectionSession session;
  late DateTime now;
  setUp(() {
    account = _ObservedAccount(achievementTestAccount(1));
    port = _NotifyingPort();
    now = DateTime.utc(2026, 10, 15);
    session = AchievementCollectionSession(
      account: account,
      port: port,
      clock: () => now,
    );
  });
  tearDown(() async {
    session.dispose();
    account.dispose();
    await port.close();
  });

  test(
    'construction starts no read; fresh and confirmed empty data are reused',
    () async {
      expect(port.requests, isEmpty);
      final loaded = session.activate();
      _complete(port, 0);
      await loaded;
      expect(session.collection.value.isReady, isTrue);
      expect(session.collection.value.earnedAt, isEmpty);
      now = now.add(const Duration(minutes: 4, seconds: 59));
      await session.activate();
      expect(port.requests, hasLength(1));
      now = now.add(const Duration(seconds: 1));
      final refreshing = session.activate();
      expect(port.requests, hasLength(2));
      expect(session.collection.value.isReady, isTrue);
      expect(session.collection.value.isRefreshing, isTrue);
      final joined = session.activate();
      expect(identical(joined, refreshing), isTrue);
      _complete(port, 1);
      await refreshing;
    },
  );

  test(
    'hidden ordinary changes mark stale, preserving snapshot and viewport',
    () async {
      final loaded = session.activate();
      _complete(port, 0, earned: true);
      await loaded;
      final epoch = session.viewEpoch;
      session.rememberScroll(300, expectedEpoch: epoch);
      port.content.add(null);
      expect(port.requests, hasLength(1));
      expect(session.collection.value.isEarned('first-entry'), isTrue);
      expect(session.scrollOffset, 300);
      expect(session.viewEpoch, epoch);
      final reopened = session.activate();
      expect(port.requests, hasLength(2));
      _complete(port, 1, earned: true);
      await reopened;
    },
  );

  test(
    'visible notifications join in-flight read and queue only one followup',
    () async {
      void visible() {}
      session.collection.addListener(visible);
      addTearDown(() => session.collection.removeListener(visible));
      final loaded = session.activate();
      for (var i = 0; i < 10; i++) {
        port.content.add(null);
      }
      expect(port.requests, hasLength(1));
      _complete(port, 0, earned: true);
      await loaded;
      await Future<void>.delayed(Duration.zero);
      expect(port.requests, hasLength(2));
      expect(session.collection.value.isEarned('first-entry'), isTrue);
      _complete(port, 1, earned: true);
      await Future<void>.delayed(Duration.zero);
      expect(port.requests, hasLength(2));
    },
  );

  test(
    'hard invalidation clears hidden data and rejects old scroll and response',
    () async {
      final loaded = session.activate();
      _complete(port, 0, earned: true);
      await loaded;
      final epoch = session.viewEpoch;
      session.rememberScroll(300, expectedEpoch: epoch);
      final pending = session.collection.refresh();
      port.hard.add(null);
      expect(session.collection.value.earnedAt, isEmpty);
      expect(session.scrollOffset, 0);
      expect(session.viewEpoch, greaterThan(epoch));
      session.rememberScroll(999, expectedEpoch: epoch);
      expect(session.scrollOffset, 0);
      _complete(port, 1, earned: true);
      await pending;
      expect(session.collection.value.isReady, isFalse);
      expect(port.requests, hasLength(2));
    },
  );

  test('generation and retained selection changes erase content without eager hidden reads', () async {
    final loaded = session.activate();
    _complete(port, 0, earned: true);
    await loaded;
    session.rememberScroll(300, expectedEpoch: session.viewEpoch);
    account.value = achievementTestAccount(2, retainedReadId: 'first');
    expect(session.collection.value.earnedAt, isEmpty);
    expect(session.scrollOffset, 0);
    expect(port.requests, hasLength(1));
    final next = session.activate();
    final epoch = session.viewEpoch;
    account.value = achievementTestAccount(2, retainedReadId: 'second');
    _complete(port, 1, earned: true);
    await next;
    expect(session.collection.value.earnedAt, isEmpty);
    expect(session.viewEpoch, greaterThan(epoch));
  });

  test('disposing releases subscriptions and ignores pending results and callbacks', () async {
    final pending = session.activate();
    final controller = session.collection;
    session.dispose();
    session.dispose();
    expect(account.subscribed, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(port.content.hasListener, isFalse);
    expect(port.hard.hasListener, isFalse);
    _complete(port, 0, earned: true);
    await pending;
    expect(controller.value.earnedAt, isEmpty);
    await session.activate();
    expect(port.requests, hasLength(1));
    expect(() => session.collection, throwsStateError);
  });
}

void _complete(_NotifyingPort port, int index, {bool earned = false}) {
  final request = port.requests[index];
  request.completion.complete(
    AchievementCollection(
      generation: request.generation,
      status: AchievementCollectionStatus.ready,
      earnedAt: earned ? {'first-entry': DateTime.utc(2026, 9, 4)} : {},
    ),
  );
}

final class _ObservedAccount extends ValueNotifier<AccountProjection> {
  _ObservedAccount(super.value);
  bool get subscribed => hasListeners;
}

final class _NotifyingPort extends DeferredAchievementPort
    implements
        AchievementCollectionChanges,
        AchievementCollectionInvalidations {
  final content = StreamController<void>.broadcast(sync: true);
  final hard = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get changes => content.stream;
  @override
  Stream<void> get invalidations => hard.stream;
  Future<void> close() async {
    await content.close();
    await hard.close();
  }
}
