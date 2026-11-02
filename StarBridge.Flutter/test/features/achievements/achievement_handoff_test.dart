import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_controller.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_session.dart';
import 'package:starbridge_flutter/features/achievements/bridge_achievement_collection.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const _id = '0123456789abcdef0123456789abcdef';
const _proof = AccountDisplayHandoff(
  displayKey: _id,
  sourceGeneration: 0,
  route: AccountRoute(
    environment: 'integration',
    authority: 'synthetic',
    subject: 'owner',
  ),
);

AccountProjection _account({
  int generation = 0,
  bool reading = false,
  bool signedIn = false,
  AccountDisplayHandoff? proof,
}) => AccountProjection(
  generation: generation,
  sessionState: signedIn
      ? AccountSessionState.signedIn
      : AccountSessionState.loading,
  operation: signedIn ? AccountOperation.none : AccountOperation.refreshing,
  profileFreshness: AccountProfileFreshness.cached,
  profile: const AccountProfile(displayName: 'Synthetic cached pilot'),
  cachedAt: DateTime.utc(2026, 10, 1),
  retainedReadId: reading ? _id : null,
  preparingDisplay: true,
  displayHandoff: proof,
  identity: const AccountIdentityProjection.unavailable(),
  compatibility: const AccountCompatibilityProjection.unavailable(),
  localeOptions: const [],
  timeZoneOptions: const [],
);

class _Port
    implements AchievementCollectionPort, AchievementCollectionInvalidations {
  final hard = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => hard.stream;
  final requests =
      <({int generation, Completer<AchievementCollection> result})>[];
  @override
  Future<AchievementCollection> read({required int generation}) {
    final result = Completer<AchievementCollection>();
    requests.add((generation: generation, result: result));
    return result.future;
  }
}

class _Mode extends ChangeNotifier implements ConnectionModeControl {
  @override
  ConnectionModeSnapshot snapshot = const ConnectionModeSnapshot(
    scope: 0,
    revision: 4,
    state: ConnectionModeState.online,
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
  void advance(int scope) {
    snapshot = ConnectionModeSnapshot(
      scope: scope,
      revision: 4,
      state: ConnectionModeState.online,
    );
    notifyListeners();
  }
}

void main() {
  for (final beforeFresh in [true, false]) {
    test(
      'confirmed mode transport scope follows only the proven generation, before fresh: $beforeFresh',
      () async {
        final account = ValueNotifier(_account(reading: true));
        final mode = _Mode();
        final port = _Port();
        final session = AchievementCollectionSession(
          account: account,
          port: port,
          mode: mode,
        );
        final controller = session.collection;
        controller.addListener(() {});
        try {
          final loaded = session.activate();
          port.requests.single.result.complete(
            AchievementCollection(
              generation: 0,
              status: AchievementCollectionStatus.ready,
              cachedAtUtc: DateTime.utc(2026, 10, 1),
              earnedAt: {'stored-award': DateTime.utc(2026, 9, 1)},
            ),
          );
          await loaded;
          final viewEpoch = session.viewEpoch;
          session.rememberScroll(300, expectedEpoch: viewEpoch);
          account.value = _account(proof: _proof);
          account.value = _account(
            generation: 1,
            signedIn: true,
            proof: _proof,
          );
          if (beforeFresh) {
            mode.advance(1);
            expect(controller.value.isEarned('stored-award'), isTrue);
          }
          port.requests.last.result.complete(
            AchievementCollection(
              generation: 1,
              status: AchievementCollectionStatus.ready,
              earnedAt: {'fresh-award': DateTime.utc(2026, 10, 1)},
            ),
          );
          await Future<void>.delayed(Duration.zero);
          if (!beforeFresh) mode.advance(1);
          expect(controller.value.isEarned('fresh-award'), isTrue);
          account.value = _account(generation: 1, signedIn: true);
          expect(controller.value.isEarned('fresh-award'), isTrue);
          expect(session.scrollOffset, 300);
          expect(session.viewEpoch, viewEpoch);
          mode.advance(9);
          expect(controller.value.isEarned('fresh-award'), isFalse);
          expect(session.scrollOffset, 0);
        } finally {
          session.dispose();
          account.dispose();
          mode.dispose();
          await port.hard.close();
        }
      },
    );
  }
  for (final boundary in [
    'missing',
    'different',
    'skipped',
    'hard',
    'proofLost',
    'unmarked',
  ]) {
    test('$boundary cannot retain cached awards through a handoff', () async {
      final account = ValueNotifier(_account(reading: true));
      final port = _Port();
      final controller = AchievementCollectionController(
        account: account,
        port: port,
      );
      try {
        port.requests.single.result.complete(
          AchievementCollection(
            generation: 0,
            status: AchievementCollectionStatus.ready,
            cachedAtUtc: boundary == 'unmarked'
                ? null
                : DateTime.utc(2026, 10, 1),
            earnedAt: {'stored-award': DateTime.utc(2026, 9, 1)},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        if (boundary == 'missing') {
          account.value = _account(generation: 1);
        } else if (boundary == 'different') {
          account.value = _account(
            proof: const AccountDisplayHandoff(
              displayKey: 'fedcba9876543210fedcba9876543210',
              sourceGeneration: 0,
              route: AccountRoute(
                environment: 'integration',
                authority: 'synthetic',
                subject: 'owner',
              ),
            ),
          );
        } else if (boundary == 'skipped') {
          account.value = _account(generation: 2, proof: _proof);
        } else {
          account.value = _account(proof: _proof);
          if (boundary == 'hard') port.hard.add(null);
          if (boundary == 'proofLost') {
            account.value = _account(
              generation: 1,
              signedIn: true,
              proof: _proof,
            );
            account.value = _account(generation: 1, signedIn: true);
            port.requests[1].result.complete(
              AchievementCollection(
                generation: 1,
                status: AchievementCollectionStatus.ready,
                earnedAt: {'late-award': DateTime.utc(2026, 9, 1)},
              ),
            );
          }
        }
        await Future<void>.delayed(Duration.zero);
        expect(controller.value.isEarned('stored-award'), isFalse);
        expect(controller.value.isEarned('late-award'), isFalse);
      } finally {
        controller.dispose();
        account.dispose();
        await port.hard.close();
      }
    });
  }

  for (final transient in [true, false]) {
    test(
      'fresh failure during proven handoff retains permanent display; transient: $transient',
      () async {
        final account = ValueNotifier(_account(reading: true));
        final port = _Port();
        final controller = AchievementCollectionController(
          account: account,
          port: port,
        );
        try {
          port.requests.single.result.complete(
            AchievementCollection(
              generation: 0,
              status: AchievementCollectionStatus.ready,
              cachedAtUtc: DateTime.utc(2026, 10, 1),
              earnedAt: {'stored-award': DateTime.utc(2026, 9, 1)},
            ),
          );
          await Future<void>.delayed(Duration.zero);
          account.value = _account(proof: _proof);
          account.value = _account(
            generation: 1,
            signedIn: true,
            proof: _proof,
          );
          port.requests.last.result.complete(
            AchievementCollection(
              generation: 1,
              status: AchievementCollectionStatus.unavailable,
              transientFailure: transient,
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(controller.value.isEarned('stored-award'), isTrue);
          expect(controller.value.refreshFailed, isTrue);
          final retried = controller.refresh();
          expect(port.requests.last.generation, 1);
          port.requests.last.result.complete(
            AchievementCollection(
              generation: 1,
              status: AchievementCollectionStatus.ready,
              earnedAt: {'fresh-award': DateTime.utc(2026, 10, 1)},
            ),
          );
          await retried;
          expect(controller.value.isEarned('fresh-award'), isTrue);
          expect(controller.value.isEarned('stored-award'), isTrue);
        } finally {
          controller.dispose();
          account.dispose();
          await port.hard.close();
        }
      },
    );
  }

  test('a visible achievement session retains its viewport through the proven handoff', () async {
    final account = ValueNotifier(_account(reading: true));
    final port = _Port();
    final session = AchievementCollectionSession(account: account, port: port);
    addTearDown(account.dispose);
    addTearDown(session.dispose);
    final collection = session.collection;
    collection.addListener(() {});
    final loaded = session.activate();
    port.requests.single.result.complete(
      AchievementCollection(
        generation: 0,
        status: AchievementCollectionStatus.ready,
        cachedAtUtc: DateTime.utc(2026, 10, 1),
        earnedAt: {'stored-award': DateTime.utc(2026, 9, 1)},
      ),
    );
    await loaded;
    final epoch = session.viewEpoch;
    session.rememberScroll(300, expectedEpoch: epoch);
    account.value = _account(proof: _proof);
    account.value = _account(generation: 1, proof: _proof);
    expect(session.scrollOffset, 300);
    expect(session.viewEpoch, epoch);
  });

  test(
    'a fresh root from another owner cannot replace the proven cached awards',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      session.acceptHostCapabilities(['achievements.read']);
      const other = BridgeAccountContext(
        environment: 'integration',
        authority: 'synthetic',
        subject: 'other',
      );
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen((request) {
        requests.add(request);
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 1,
              accountContext: other,
              status: 'ok',
              payload: request.name == 'account.getCurrent'
                  ? const {'schemaVersion': 1, 'state': 'signedIn'}
                  : {
                      'schemaVersion': 1,
                      'earnedAt': {'other-award': '2026-09-01T00:00:00Z'},
                    },
            ),
          ),
        );
      });
      try {
        final result = await BridgeAchievementCollection(
          session,
          displayHandoff: () => _proof,
        ).read(generation: 1);
        expect(result.status, AchievementCollectionStatus.unavailable);
        expect(requests.map((r) => r.name), ['account.getCurrent']);
      } finally {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    },
  );

  test('materialized cached awards survive proven restore until the fresh collection arrives', () async {
    final account = ValueNotifier(_account(reading: true));
    final port = _Port();
    final controller = AchievementCollectionController(
      account: account,
      port: port,
    );
    addTearDown(controller.dispose);
    addTearDown(account.dispose);
    port.requests.single.result.complete(
      AchievementCollection(
        generation: 0,
        status: AchievementCollectionStatus.ready,
        cachedAtUtc: DateTime.utc(2026, 10, 1),
        earnedAt: {'stored-award': DateTime.utc(2026, 9, 1)},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.value.isEarned('stored-award'), isTrue);
    account.value = _account(proof: _proof);
    expect(controller.value.isEarned('stored-award'), isTrue);
    expect(port.requests, hasLength(1));
    account.value = _account(generation: 1, proof: _proof);
    expect(controller.value.isEarned('stored-award'), isTrue);
    expect(controller.value.generation, 1);
    expect(port.requests, hasLength(1));
    account.value = _account(generation: 1, signedIn: true, proof: _proof);
    expect(controller.value.isEarned('stored-award'), isTrue);
    expect(controller.value.isRefreshing, isTrue);
    expect(port.requests, hasLength(2));
    port.requests.last.result.complete(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
        earnedAt: {'fresh-award': DateTime.utc(2026, 10, 1)},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.value.isEarned('stored-award'), isTrue);
    expect(controller.value.isEarned('fresh-award'), isTrue);
    expect(controller.value.cachedAtUtc, isNull);
    account.value = _account(generation: 1, signedIn: true);
    expect(controller.value.isEarned('fresh-award'), isTrue);
    expect(port.requests, hasLength(2));
  });
}
