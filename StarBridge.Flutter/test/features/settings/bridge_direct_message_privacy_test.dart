import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/bridge_direct_message_privacy.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test('reads and writes the account-scoped direct message policy', () async {
    final harness = Harness();
    addTearDown(harness.close);
    final read = await harness.adapter.read();
    expect(read.allowStrangerDirectMessages, isFalse);

    final saved = await harness.adapter.save(true);
    expect(saved.outcome, DirectMessagePrivacyWriteOutcome.completed);
    expect(saved.snapshot?.allowStrangerDirectMessages, isTrue);
    final write = harness.requests.singleWhere(
      (request) => request.name == 'directMessages.privacyWrite',
    );
    expect(write.accountContext?.subject, 'test-subject');
    expect(write.payload, {
      'schemaVersion': 1,
      'allowStrangerDirectMessages': true,
    });
  });

  test('unknown write result never changes the confirmed value', () async {
    final harness = Harness(
      writeError: 'directMessages.privacy_outcome_unknown',
    );
    addTearDown(harness.close);
    final module = DirectMessagePrivacyModule(harness.adapter);
    addTearDown(module.dispose);
    await module.initialize();

    expect(await module.save(true), isFalse);
    expect(
      module.projection.value.snapshot.allowStrangerDirectMessages,
      isFalse,
    );
    expect(
      module.projection.value.failure,
      DirectMessagePrivacyFailure.outcomeUnknown,
    );
    expect(harness.privacyWrites, 1);
    expect(harness.privacyReads, 4);
  });

  test(
    'unknown write is confirmed by bounded readback without replay',
    () async {
      final harness = Harness(
        writeError: 'directMessages.privacy_outcome_unknown',
        applyUnknownWrite: true,
      );
      addTearDown(harness.close);
      final module = DirectMessagePrivacyModule(harness.adapter);
      addTearDown(module.dispose);
      await module.initialize();

      expect(await module.save(true), isTrue);
      expect(
        module.projection.value.snapshot.allowStrangerDirectMessages,
        isTrue,
      );
      expect(module.projection.value.failure, isNull);
      expect(harness.privacyWrites, 1);
      expect(harness.privacyReads, 2);
    },
  );

  test('account change cancels a pending confirmation readback', () async {
    final harness = Harness(
      writeError: 'directMessages.privacy_outcome_unknown',
      confirmationDelays: const [Duration(minutes: 1)],
    );
    addTearDown(harness.close);

    final pending = harness.adapter.save(true);
    await _waitFor(() => harness.privacyWrites == 1);
    await Future<void>.delayed(Duration.zero);
    await harness.sendAccountChanged();

    final result = await pending.timeout(const Duration(seconds: 1));
    expect(result.outcome, DirectMessagePrivacyWriteOutcome.rejected);
    expect(result.failure, DirectMessagePrivacyFailure.identityUnavailable);
    expect(harness.privacyWrites, 1);
    expect(harness.privacyReads, 0);
  });

  test(
    'missing capability stays unavailable without sending a request',
    () async {
      final harness = Harness(capabilities: const []);
      addTearDown(harness.close);
      final read = await harness.adapter.read();
      expect(read.availability, DirectMessagePrivacyAvailability.unavailable);
      expect(harness.requests, isEmpty);
    },
  );
}

class Harness {
  Harness({
    this.writeError,
    this.applyUnknownWrite = false,
    List<Duration> confirmationDelays = const [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ],
    List<String> capabilities = const [
      'directMessages.privacyRead',
      'directMessages.privacyWrite',
    ],
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    session.acceptHostCapabilities(capabilities);
    adapter = BridgeDirectMessagePrivacy(
      session,
      confirmationDelays: confirmationDelays,
    );
    subscription = connection.incoming.listen((request) {
      requests.add(request);
      if (request.name != 'bridge.cancel') unawaited(_reply(request));
    });
  }

  final String? writeError;
  final bool applyUnknownWrite;
  final requests = <BridgeEnvelope>[];
  bool serverValue = false;
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final BridgeDirectMessagePrivacy adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;

  int get privacyReads => requests
      .where((request) => request.name == 'directMessages.privacyRead')
      .length;

  int get privacyWrites => requests
      .where((request) => request.name == 'directMessages.privacyWrite')
      .length;

  Future<void> _reply(BridgeEnvelope request) {
    if (request.name == 'directMessages.privacyWrite' &&
        (writeError == null || applyUnknownWrite)) {
      serverValue = request.payload['allowStrangerDirectMessages']! as bool;
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
            request.name == 'directMessages.privacyWrite' && writeError != null
            ? 'error'
            : 'ok',
        error:
            request.name == 'directMessages.privacyWrite' && writeError != null
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
                'allowStrangerDirectMessages': serverValue,
                'updatedAt': '2026-09-12T12:00:00Z',
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

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition was not reached in time.');
}
