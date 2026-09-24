import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_safety.dart';
import 'package:starbridge_flutter/features/account/bridge_account_safety.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

void main() {
  for (final state in ['signedIn', 'legacySignedIn']) {
    test(
      '$state uses the current account context with no alternate login',
      () async {
        final connection = _Connection()..state = state;
        final session =
            BridgeClientSession(connection: connection, sessionGeneration: 1)
              ..acceptHostCapabilities([
                'accountSafety.read',
                'accountSafety.appeal',
              ]);
        final port = BridgeAccountSafety(session);
        final snapshot = await port.read();
        expect(snapshot.restrictions, isEmpty);
        expect(connection.sent.map((e) => e.name), [
          'account.getCurrent',
          'accountSafety.read',
        ]);
        expect(connection.sent.last.accountContext, same(connection.owner));
        expect(
          await port.submit('sanction', 'reason', 'same-intent'),
          AccountAppealOutcome.submitted,
        );
        expect(connection.sent.last.payload, {
          'schemaVersion': 1,
          'sanctionId': 'sanction',
          'details': 'reason',
          'clientRequestId': 'same-intent',
        });
        port.dispose();
        await session.close();
      },
    );
  }
  test('signed out never sends a domain read or submission', () async {
    final connection = _Connection()..state = 'signedOut';
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 1,
    )..acceptHostCapabilities(['accountSafety.read', 'accountSafety.appeal']);
    final port = BridgeAccountSafety(session);
    await expectLater(
      port.read(),
      throwsA(
        isA<AccountSafetyException>().having(
          (e) => e.failure,
          'failure',
          AccountSafetyFailure.signedOut,
        ),
      ),
    );
    expect(
      await port.submit('sanction', 'reason', 'intent'),
      AccountAppealOutcome.sessionChanged,
    );
    expect(
      connection.sent.every((e) => e.name == 'account.getCurrent'),
      isTrue,
    );
    port.dispose();
    await session.close();
  });
  test('malformed response is not empty success and uncertain submit is not repeated', () async {
    final connection = _Connection()..malformed = true;
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 1,
    )..acceptHostCapabilities(['accountSafety.read', 'accountSafety.appeal']);
    final port = BridgeAccountSafety(session);
    await expectLater(
      port.read(),
      throwsA(
        isA<AccountSafetyException>().having(
          (e) => e.failure,
          'failure',
          AccountSafetyFailure.invalid,
        ),
      ),
    );
    expect(
      await port.submit('sanction', 'reason', 'intent'),
      AccountAppealOutcome.unknown,
    );
    expect(
      connection.sent.where((e) => e.name == 'accountSafety.appeal'),
      hasLength(1),
    );
    port.dispose();
    await session.close();
  });
}

class _Connection implements BridgeConnection {
  final stream = StreamController<BridgeEnvelope>();
  final sent = <BridgeEnvelope>[];
  String state = 'signedIn';
  bool malformed = false;
  final owner = const BridgeAccountContext(
    environment: 'test',
    authority: 'starbridge-relay-test',
    subject: 'synthetic',
  );
  @override
  Stream<BridgeEnvelope> get incoming => stream.stream;
  @override
  Future<void> send(BridgeEnvelope request) async {
    sent.add(request);
    final account = request.name == 'account.getCurrent';
    stream.add(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: state == 'signedOut' ? null : owner,
        status: 'ok',
        payload: account
            ? {'schemaVersion': 1, 'state': state}
            : malformed
            ? {}
            : request.name == 'accountSafety.appeal'
            ? {'schemaVersion': 1, 'outcome': 'submitted'}
            : {
                'schemaVersion': 1,
                'sanctions': [],
                'appeals': [],
                'restrictions': [],
                'updatedAt': '2026-09-13T12:00:00Z',
              },
      ),
    );
  }

  @override
  Future<void> close() => stream.close();
}
