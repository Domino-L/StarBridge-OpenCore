import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/bridge_friend_request_privacy.dart';
import 'package:starbridge_flutter/features/settings/friend_request_privacy_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test('reads the default and writes the account-scoped setting', () async {
    final harness = Harness();
    addTearDown(harness.close);

    final initial = await harness.adapter.read();
    expect(initial.allowFriendRequests, isTrue);
    expect(initial.updatedAt, isNull);

    final saved = await harness.adapter.save(false);
    expect(saved.outcome, FriendRequestPrivacyWriteOutcome.completed);
    expect(saved.snapshot?.allowFriendRequests, isFalse);
    final write = harness.requests.singleWhere(
      (request) => request.name == 'friendRequests.privacyWrite',
    );
    expect(write.accountContext?.subject, 'test-subject');
    expect(write.payload, {'schemaVersion': 1, 'allowFriendRequests': false});
  });

  test(
    'uncertain write is confirmed by bounded readback without replay',
    () async {
      final harness = Harness(
        writeError: 'friendRequests.privacy_outcome_unknown',
        applyUnknownWrite: true,
      );
      addTearDown(harness.close);
      final module = FriendRequestPrivacyModule(harness.adapter);
      addTearDown(module.dispose);
      await module.initialize();

      expect(await module.save(false), isTrue);
      expect(module.projection.value.snapshot.allowFriendRequests, isFalse);
      expect(module.projection.value.failure, isNull);
      expect(harness.privacyWrites, 1);
      expect(harness.privacyReads, 2);
    },
  );

  test('unconfirmed write keeps the last authoritative value', () async {
    final harness = Harness(
      writeError: 'friendRequests.privacy_outcome_unknown',
    );
    addTearDown(harness.close);
    final module = FriendRequestPrivacyModule(harness.adapter);
    addTearDown(module.dispose);
    await module.initialize();

    expect(await module.save(false), isFalse);
    expect(module.projection.value.snapshot.allowFriendRequests, isTrue);
    expect(
      module.projection.value.failure,
      FriendRequestPrivacyFailure.outcomeUnknown,
    );
    expect(harness.privacyWrites, 1);
    expect(harness.privacyReads, 4);
  });

  test('account change cancels a pending confirmation readback', () async {
    final harness = Harness(
      writeError: 'friendRequests.privacy_outcome_unknown',
      confirmationDelays: const [Duration(minutes: 1)],
    );
    addTearDown(harness.close);

    final pending = harness.adapter.save(false);
    await _waitFor(() => harness.privacyWrites == 1);
    await harness.sendAccountChanged();

    final result = await pending.timeout(const Duration(seconds: 1));
    expect(result.outcome, FriendRequestPrivacyWriteOutcome.rejected);
    expect(result.failure, FriendRequestPrivacyFailure.identityUnavailable);
    expect(harness.privacyWrites, 1);
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var index = 0; index < 50 && !condition(); index++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

final class Harness {
  Harness({
    this.writeError,
    this.applyUnknownWrite = false,
    List<Duration> confirmationDelays = const [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ],
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities(const [
      'friendRequests.privacyRead',
      'friendRequests.privacyWrite',
    ]);
    adapter = BridgeFriendRequestPrivacy(
      session,
      confirmationDelays: confirmationDelays,
      confirmationRequestTimeout: const Duration(seconds: 1),
    );
    subscription = connection.incoming.listen((request) {
      requests.add(request);
      unawaited(_reply(request));
    });
  }

  final String? writeError;
  final bool applyUnknownWrite;
  final requests = <BridgeEnvelope>[];
  bool serverValue = true;
  DateTime? updatedAt;
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final BridgeFriendRequestPrivacy adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;

  int get privacyReads => requests
      .where((request) => request.name == 'friendRequests.privacyRead')
      .length;

  int get privacyWrites => requests
      .where((request) => request.name == 'friendRequests.privacyWrite')
      .length;

  Future<void> _reply(BridgeEnvelope request) {
    if (request.name == 'friendRequests.privacyWrite' &&
        (writeError == null || applyUnknownWrite)) {
      serverValue = request.payload['allowFriendRequests']! as bool;
      updatedAt = DateTime.utc(2026, 9, 12, 12);
    }
    return connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: const BridgeAccountContext(
          environment: 'test',
          authority: 'scm',
          subject: 'test-subject',
        ),
        status:
            request.name == 'friendRequests.privacyWrite' && writeError != null
            ? 'error'
            : 'ok',
        error:
            request.name == 'friendRequests.privacyWrite' && writeError != null
            ? BridgeErrorBody(
                code: writeError!,
                message: 'private host detail',
                retryable: false,
              )
            : null,
        payload: request.name == 'account.getCurrent'
            ? {'schemaVersion': 1, 'state': 'signedIn'}
            : {
                'schemaVersion': 1,
                'allowFriendRequests': serverValue,
                'updatedAt': updatedAt?.toIso8601String(),
              },
      ),
    );
  }

  Future<void> sendAccountChanged() => connection.send(
    const BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'account.changed',
      sessionGeneration: 5,
      sequence: 0,
      payload: {},
    ),
  );

  Future<void> close() async {
    await adapter.close();
    await subscription.cancel();
    await session.close();
    await connection.close();
  }
}
