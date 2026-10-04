import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_payload_decoder.dart';
import 'package:starbridge_flutter/features/account/handle_mismatch_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

final class _Fixture {
  _Fixture() {
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 7)
      ..acceptHostCapabilities([
        'gameIdentity.prepareHandleChange',
        'gameIdentity.notifyMismatch',
        'gameIdentity.confirmHandleChange',
        'gameIdentity.cancelHandleChange',
      ]);
    port = BridgeHandleMismatchPort(session);
    subscription = pair.host.incoming.listen((request) async {
      if (request.name == 'bridge.cancel') return;
      requests.add(request);
      final accountRead = request.name == 'account.getCurrent';
      if (!accountRead) await barrier?.future;
      if (closed) return;
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'ok',
          accountContext: accountRead ? owner : responseOwner,
          payload: accountRead
              ? {'schemaVersion': 1, 'state': 'legacySignedIn'}
              : request.name == 'gameIdentity.notifyMismatch'
              ? {
                  'schemaVersion': 1,
                  'submitted': true,
                  'reason': 'submitted',
                  'authoritativeHandle': 'Pilot_Alpha',
                  'detectedHandle': 'Pilot-Alpha',
                }
              : data,
        ),
      );
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeHandleMismatchPort port;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  static const owner = BridgeAccountContext(
    environment: 'test',
    authority: 'synthetic',
    subject: 'owner-one',
  );
  BridgeAccountContext responseOwner = owner;
  Completer<void>? barrier;
  bool closed = false;
  Map<String, Object?> data = {
    'schemaVersion': 1,
    'state': 'unknown',
    'expectedHandle': 'Pilot_Alpha',
    'detectedHandle': 'Pilot-Alpha',
    'scmBindingState': 'unknown',
  };
  Future<void> close() async {
    closed = true;
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}

void main() {
  test(
    'compatibility ready has opaque ticket; only explicit confirm writes',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      final id = 'a' * 32;
      fixture.data = {
        ...fixture.data,
        'state': 'ready',
        'mode': 'legacyCompatibility',
        'confirmationId': id,
      };
      final ready = await fixture.port.check(7);
      expect(ready.confirmationId, id);
      expect(
        fixture.requests.where((r) => r.name.contains('confirmHandle')),
        isEmpty,
      );
      fixture.data = {'schemaVersion': 1, 'outcome': 'confirmed'};
      await fixture.port.confirm(7, id);
      final sent = fixture.requests.singleWhere(
        (r) => r.name.contains('confirmHandle'),
      );
      expect(sent.payload, {'schemaVersion': 1, 'confirmationId': id});
      expect(sent.accountContext?.toJson(), _Fixture.owner.toJson());
    },
  );
  test('read and notify send only schema under current owner; no client Handle text', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final result = await fixture.port.check(7);
    expect(result.state, HandleCheckState.unknown);
    expect(result.expectedHandle, 'Pilot_Alpha');
    expect(result.detectedHandle, 'Pilot-Alpha');
    expect((await fixture.port.notifyBackground(7))?.key, (
      7,
      'pilot_alpha',
      'pilot-alpha',
    ));
    final commands = fixture.requests.where(
      (r) => r.name != 'account.getCurrent',
    );
    expect(commands, hasLength(2));
    for (final command in commands) {
      expect(command.payload, {'schemaVersion': 1});
      expect(command.accountContext?.toJson(), _Fixture.owner.toJson());
      expect(command.sessionGeneration, 7);
    }
  });

  for (final patch in <Map<String, Object?>>[
    {'state': 'ready', 'confirmationId': 'not-supported'},
    {'outcome': 'updated'},
    {'confirmationId': 'not-supported'},
    {'scmBindingState': 'unbound'},
    {'state': 'bound', 'scmBindingState': 'unknown'},
    {'detectedHandle': null},
    {'detectedHandle': 'pilot_alpha'},
    {'detectedHandle': 'bad\nhandle'},
    {'schemaVersion': 1.0},
  ]) {
    test('reject writable, unproven or malformed response $patch', () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      fixture.data = {...fixture.data, ...patch};
      await expectLater(fixture.port.check(7), throwsFormatException);
      expect(
        fixture.requests.where((r) => r.name.contains('confirm')),
        isEmpty,
      );
    });
  }

  test(
    'foreign owner response is rejected even at the same generation',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      fixture.responseOwner = const BridgeAccountContext(
        environment: 'test',
        authority: 'synthetic',
        subject: 'other-owner',
      );
      await expectLater(fixture.port.check(7), throwsFormatException);
      expect(await fixture.port.notifyBackground(7), isNull);
    },
  );

  test(
    'late response from previous generation cannot pass typed seam',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      fixture.barrier = Completer<void>();
      final pending = fixture.port.check(7);
      final assertion = expectLater(
        pending,
        throwsA(isA<BridgeStaleGenerationException>()),
      );
      for (var i = 0; i < 10 && fixture.requests.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(fixture.requests, hasLength(2));
      fixture.session.advanceGeneration(8);
      fixture.barrier!.complete();
      await assertion;
      final count = fixture.requests.length;
      expect(await fixture.port.notifyBackground(7), isNull);
      expect(fixture.requests.length, count);
    },
  );

  test(
    'missing capabilities fail closed before any transport request',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      fixture.session.acceptHostCapabilities([]);
      await expectLater(fixture.port.check(7), throwsFormatException);
      expect(await fixture.port.notifyBackground(7), isNull);
      expect(fixture.requests, isEmpty);
    },
  );

  test('old Host absent binding defaults unknown, not unbound', () {
    final policy = AccountPayloadDecoder.identity({
      'schemaVersion': 1,
      'state': 'mismatch',
      'sensitiveWritesAllowed': false,
      'authoritativeHandle': 'Pilot_Alpha',
    });
    expect(policy.scmBindingState, AccountScmBindingState.unknown);
    expect(policy.detectedHandle, isNull);
  });
}
