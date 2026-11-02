import 'dart:async';

import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_controller.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/bridge_achievement_collection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'achievement_collection_controller_test.dart'
    show achievementTestAccount;

class _Mode extends ChangeNotifier implements ConnectionModeControl {
  @override
  ConnectionModeSnapshot snapshot = ConnectionModeSnapshot(
    scope: 1,
    revision: 4,
    state: ConnectionModeState.offline,
    offlineAccount: OfflineAccountDisplay(
      'Synthetic pilot',
      DateTime.utc(2026, 9, 4),
    ),
  );
  @override
  bool get failed => false;
  @override
  bool get busy => false;
  @override
  bool get allowsOnlineTraffic => snapshot.state == ConnectionModeState.online;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
  void clear() {
    snapshot = const ConnectionModeSnapshot(
      scope: 2,
      revision: 5,
      state: ConnectionModeState.local,
    );
    notifyListeners();
  }
}

class _Harness {
  _Harness({
    bool supported = true,
    ConnectionModeControl? mode,
    String? Function()? retainedReadId,
  }) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    if (supported) session.acceptHostCapabilities(['achievements.read']);
    port = BridgeAchievementCollection(
      session,
      mode: mode,
      retainedReadId: retainedReadId,
    );
    incoming = pair.host.incoming.listen((request) {
      if (request.name == 'bridge.cancel') return;
      requests.add(request);
      if (hold &&
          (request.name == 'achievements.read' ||
              request.name == 'onboarding.mode.achievements' ||
              request.name == 'account.offlineData.read')) {
        held = request;
        return;
      }
      respond(request);
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeAchievementCollection port;
  late final StreamSubscription<BridgeEnvelope> incoming;
  final requests = <BridgeEnvelope>[];
  Map<String, Object?> earned = {};
  Object? progress;
  int schema = 1;
  String state = 'signedIn';
  bool wrongOwner = false, hold = false, fail = false;
  String failureCode = 'achievements.unavailable';
  String cachedAt = '2026-09-04T12:00:30Z';
  String? synchronizedAt;
  bool refreshFailed = false;
  BridgeEnvelope? held;
  void respond(BridgeEnvelope request) {
    unawaited(
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext:
              request.name == 'onboarding.mode.achievements' ||
                  request.name == 'account.offlineData.read'
              ? null
              : BridgeAccountContext(
                  environment: 'test',
                  authority: 'scm',
                  subject: wrongOwner && request.name == 'achievements.read'
                      ? 'other'
                      : 'synthetic-achievement',
                ),
          status: fail && request.name == 'achievements.read' ? 'error' : 'ok',
          error: fail && request.name == 'achievements.read'
              ? BridgeErrorBody(
                  code: failureCode,
                  message: 'synthetic outage',
                  retryable: true,
                )
              : null,
          payload:
              request.name == 'onboarding.mode.achievements' ||
                  request.name == 'account.offlineData.read'
              ? {
                  'schemaVersion': 1,
                  'cachedAtUtc': cachedAt,
                  'collection': {
                    'schemaVersion': schema,
                    'earnedAt': earned,
                    if (progress != null) 'progress': progress,
                  },
                }
              : request.name == 'account.getCurrent'
              ? {'schemaVersion': 1, 'state': state}
              : {
                  'schemaVersion': schema,
                  'earnedAt': earned,
                  if (progress != null) 'progress': progress,
                  if (synchronizedAt != null)
                    'synchronizedAtUtc': synchronizedAt,
                  if (refreshFailed) 'refreshFailed': true,
                },
        ),
      ),
    );
  }

  Future<void> changed() => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'achievements.changed',
      sessionGeneration: 1,
      sequence: 1,
      payload: const {'schemaVersion': 1},
    ),
  );
  Future<void> close() async {
    await incoming.cancel();
    await session.close();
    await pair.host.close();
  }
}

void main() {
  test(
    'cached Host display preserves its confirmation time and sync failure',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.earned = {'first-entry': '2026-09-04T12:00:30Z'};
      h.synchronizedAt = '2026-09-05T12:00:30Z';
      h.refreshFailed = true;
      final collection = await h.port.read(generation: 1);
      expect(collection.isEarned('first-entry'), isTrue);
      expect(collection.synchronizedAtUtc, DateTime.utc(2026, 9, 5, 12, 0, 30));
      expect(collection.refreshFailed, isTrue);
    },
  );
  for (final failure in [
    'achievements.forbidden',
    'account.identity_unavailable',
    'bridge.disconnected',
    'bridge.host_error',
  ]) {
    test(
      'cached collection handles $failure without treating retryable as authorization',
      () async {
        final h = _Harness();
        final account = ValueNotifier(achievementTestAccount(1));
        h.earned = {'first-entry': '2026-09-04T12:00:00Z'};
        final controller = AchievementCollectionController(
          account: account,
          port: h.port,
        );
        addTearDown(() async {
          controller.dispose();
          account.dispose();
          await h.close();
        });
        await controller.refresh();
        expect(controller.value.isEarned('first-entry'), isTrue);
        h.fail = true;
        h.failureCode = failure;
        await controller.refresh();
        expect(controller.value.isReady, isTrue);
        expect(controller.value.isEarned('first-entry'), isTrue);
        expect(controller.value.refreshFailed, isTrue);
      },
    );
  }

  test(
    'a schema mismatch rejects new data while preserving confirmed display',
    () async {
      final h = _Harness();
      final account = ValueNotifier(achievementTestAccount(1));
      h.earned = {'first-entry': '2026-09-04T12:00:00Z'};
      final controller = AchievementCollectionController(
        account: account,
        port: h.port,
      );
      addTearDown(() async {
        controller.dispose();
        account.dispose();
        await h.close();
      });
      await controller.refresh();
      expect(controller.value.isEarned('first-entry'), isTrue);
      h.schema = 99;
      await controller.refresh();
      expect(controller.value.isReady, isTrue);
      expect(controller.value.refreshFailed, isTrue);
      expect(controller.value.isEarned('first-entry'), isTrue);
    },
  );

  test(
    'network outage reads only retained collection and rejects retired lease',
    () async {
      String? id = '0123456789abcdef0123456789abcdef';
      final h = _Harness(retainedReadId: () => id);
      addTearDown(h.close);
      h.earned = {'first-entry': '2026-09-04T12:00:00Z'};
      final result = await h.port.read(generation: 1);
      expect(result.isEarned('first-entry'), isTrue);
      expect(result.cachedAtUtc, isNotNull);
      expect(h.requests.single.name, 'account.offlineData.read');
      expect(h.requests.single.accountContext, isNull);
      expect(h.requests.single.payload['kind'], 'achievements');
      h.hold = true;
      final late = h.port.read(generation: 1);
      await Future<void>.delayed(Duration.zero);
      id = null;
      h.respond(h.held!);
      expect((await late).status, AchievementCollectionStatus.unavailable);
    },
  );
  test('offline collection is read-only and works with a retained signed-out projection', () async {
    final mode = _Mode();
    final h = _Harness(mode: mode, supported: false);
    final account = ValueNotifier(achievementTestAccount(1, signedIn: false));
    h.earned = {'first-entry': '2026-09-04T12:00:30Z'};
    final controller = AchievementCollectionController(
      account: account,
      port: h.port,
      mode: mode,
    );
    addTearDown(() async {
      controller.dispose();
      account.dispose();
      mode.dispose();
      await h.close();
    });
    await controller.refresh();
    expect(controller.value.isEarned('first-entry'), isTrue);
    expect(controller.value.cachedAtUtc, DateTime.parse(h.cachedAt));
    expect(
      h.requests.every(
        (r) =>
            r.name == 'onboarding.mode.achievements' &&
            r.accountContext == null &&
            r.payload['revision'] == 4,
      ),
      isTrue,
    );
    mode.clear();
    expect(controller.value.earnedAt, isEmpty);
    expect(controller.value.status, AchievementCollectionStatus.unavailable);
  });
  test('offline parser rejects malformed dates and discontinuous collection without remote fallback', () async {
    final mode = _Mode();
    final h = _Harness(mode: mode);
    addTearDown(() async {
      mode.dispose();
      await h.close();
    });
    h.cachedAt = 'invalid';
    expect((await h.port.read(generation: 1)).isReady, isFalse);
    h.cachedAt = '2026-09-04T12:00:30Z';
    h.earned = {'hangar-home-2': h.cachedAt};
    expect((await h.port.read(generation: 1)).isReady, isFalse);
    h.earned = {};
    expect((await h.port.read(generation: 1)).isReady, isTrue);
    expect(
      h.requests.every((r) => r.name == 'onboarding.mode.achievements'),
      isTrue,
    );
  });
  test(
    'late offline collection is discarded after mode owner changes',
    () async {
      final mode = _Mode();
      final h = _Harness(mode: mode);
      addTearDown(() async {
        mode.dispose();
        await h.close();
      });
      h.hold = true;
      final pending = h.port.read(generation: 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      mode.clear();
      h.respond(h.held!);
      expect((await pending).isReady, isFalse);
      expect(h.requests.length, 1);
    },
  );
  test(
    'series projection validates rank continuity and bounded progress',
    () async {
      final h = _Harness();
      final at = DateTime.utc(2026, 10, 9).toIso8601String();
      h.earned = {'hangar-home-1': at, 'hangar-home-2': at};
      h.progress = {'hangar-home': 4};
      final good = await h.port.read(generation: 1);
      expect(good.rank('hangar-home'), 2);
      expect(good.progressFor('hangar-home'), 4);
      h.progress = {'hangar-home': 1};
      expect((await h.port.read(generation: 1)).isReady, isFalse);
      h.progress = {'hangar-paths': 7};
      expect((await h.port.read(generation: 1)).isReady, isFalse);
      h.progress = {'hangar-home': 4};
      h.earned = {'hangar-home-2': at};
      expect((await h.port.read(generation: 1)).isReady, isFalse);
      h.earned = {};
      h.progress = null;
      expect(
        (await h.port.read(generation: 1)).progressFor('hangar-home'),
        isNull,
      );
    },
  );
  test(
    'accepts the Stanton progress the server sends beside hangar series',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.progress = {
        'hangar-home': 0,
        'hangar-collection': 0,
        'hangar-paths': 0,
        'journey-stanton': 2,
      };
      final good = await h.port.read(generation: 1);
      expect(good.isReady, isTrue);
      expect(good.progressFor('journey-stanton'), 2);
      h.progress = {'journey-stanton': 5};
      expect((await h.port.read(generation: 1)).isReady, isFalse);
      h.progress = {'journey-unknown': 1};
      expect((await h.port.read(generation: 1)).isReady, isFalse);
    },
  );
  // Host forwards the server's read: Java writes Z, a Host snapshot writes +00:00.
  const realEarned = {
    'first-entry': '2026-10-30T20:33:12.123Z',
    'hangar-home-1': '2026-10-30T20:33:13.5+00:00',
    'journey-lorville': '2026-10-30T20:33:14+00:00',
  };
  const realProgress = {
    'hangar-home': 2,
    'hangar-collection': 2,
    'hangar-paths': 1,
    'journey-stanton': 1,
  };
  void expectRealCollection(AchievementCollection collection) {
    expect(collection.isReady, isTrue);
    expect(collection.isEarned('first-entry'), isTrue);
    expect(collection.isEarned('journey-lorville'), isTrue);
    expect(collection.rank('hangar-home'), 1);
    expect(collection.progressFor('hangar-home'), 2);
    expect(collection.progressFor('journey-stanton'), 1);
  }

  test('a live read with the real response shape stays readable', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.earned = realEarned;
    h.progress = realProgress;
    h.synchronizedAt = '2026-10-30T20:33:15.1+00:00';
    final collection = await h.port.read(generation: 1);
    expectRealCollection(collection);
    expect(collection.refreshFailed, isFalse);
    expect(collection.cachedAtUtc, isNull);
  });
  test('a retained snapshot holding Stanton progress stays readable', () async {
    final h = _Harness(retainedReadId: () => 'retained-read');
    addTearDown(h.close);
    h.earned = realEarned;
    h.progress = realProgress;
    final collection = await h.port.read(generation: 1);
    expect(h.requests.single.name, 'account.offlineData.read');
    expectRealCollection(collection);
    expect(collection.cachedAtUtc, DateTime.parse(h.cachedAt));
  });
  test('an offline snapshot holding Stanton progress stays readable', () async {
    final h = _Harness(mode: _Mode());
    addTearDown(h.close);
    h.earned = realEarned;
    h.progress = realProgress;
    final collection = await h.port.read(generation: 1);
    expect(h.requests.single.name, 'onboarding.mode.achievements');
    expectRealCollection(collection);
    expect(collection.cachedAtUtc, DateTime.parse(h.cachedAt));
  });
  test(
    'reads authenticated cloud collection and never writes awards',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.earned = {'first-entry': '2026-09-04T12:00:30Z'};
      final value = await h.port.read(generation: 1);
      expect(value.isEarned('first-entry'), isTrue);
      expect(
        value.earnedAt['first-entry'],
        DateTime.utc(2026, 9, 4, 12, 0, 30),
      );
      expect(h.requests.map((r) => r.name), [
        'account.getCurrent',
        'achievements.read',
      ]);
      expect(h.requests.last.accountContext?.subject, 'synthetic-achievement');
    },
  );
  test(
    'unsupported legacy session and stale generation stay unavailable',
    () async {
      final unsupported = _Harness(supported: false);
      addTearDown(unsupported.close);
      expect(
        (await unsupported.port.read(generation: 1)).status,
        AchievementCollectionStatus.unavailable,
      );
      expect(unsupported.requests, isEmpty);
      final h = _Harness();
      addTearDown(h.close);
      h.state = 'legacySignedIn';
      expect((await h.port.read(generation: 1)).isReady, isFalse);
      expect(h.requests.where((r) => r.name == 'achievements.read'), isEmpty);
      expect((await h.port.read(generation: 2)).isReady, isFalse);
    },
  );
  test(
    'wrong owner and malformed cloud records cannot mark complete',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.wrongOwner = true;
      h.earned = {'first-entry': '2026-09-04T12:00:30Z'};
      expect((await h.port.read(generation: 1)).isReady, isFalse);
      h.wrongOwner = false;
      for (final date in [
        'not-a-date',
        '2026-09-04T12:00:30',
        '2100-01-01T00:00:00Z',
        5,
      ]) {
        h.earned = {'first-entry': date};
        expect((await h.port.read(generation: 1)).isReady, isFalse);
      }
      h.schema = 2;
      h.earned = {};
      expect((await h.port.read(generation: 1)).isReady, isFalse);
    },
  );
  test('cloud invalidation updates the existing account collection', () async {
    final h = _Harness();
    addTearDown(h.close);
    final account = ValueNotifier(achievementTestAccount(1));
    addTearDown(account.dispose);
    final controller = AchievementCollectionController(
      account: account,
      port: h.port,
    );
    addTearDown(controller.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.value.isReady, isTrue);
    expect(controller.value.earnedAt, isEmpty);
    h.earned = {'first-entry': '2026-09-04T12:00:30Z'};
    await h.changed();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.value.isEarned('first-entry'), isTrue);
    h.fail = true;
    await controller.refresh();
    expect(controller.value.status, AchievementCollectionStatus.ready);
    expect(controller.value.isEarned('first-entry'), isTrue);
    expect(controller.value.refreshFailed, isTrue);
  });
  test(
    'same-account bootstrap refresh never clears confirmed awards',
    () async {
      final h = _Harness();
      h.earned = {'first-entry': '2026-09-04T12:00:30Z'};
      final account = ValueNotifier(achievementTestAccount(1));
      final controller = AchievementCollectionController(
        account: account,
        port: h.port,
      );
      addTearDown(() async {
        controller.dispose();
        account.dispose();
        await h.close();
      });
      await controller.ensureLoaded();
      expect(controller.value.isEarned('first-entry'), isTrue);
      h.hold = true;
      await h.pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'bootstrap.invalidated',
          sessionGeneration: 1,
          sequence: 1,
          payload: const {'schemaVersion': 1},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        controller.value.isEarned('first-entry'),
        isTrue,
        reason:
            'A same-account refresh must not paint earned artwork as locked.',
      );
      h.respond(h.held!);
      await controller.ensureLoaded();
    },
  );
  test(
    'late result after generation change cannot restore old awards',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.hold = true;
      final reading = h.port.read(generation: 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      h.session.advanceGeneration(2);
      h.earned = {'first-entry': '2026-09-04T12:00:30Z'};
      await expectLater(
        reading,
        throwsA(isA<BridgeStaleGenerationException>()),
      );
      h.respond(h.held!);
    },
  );
}
