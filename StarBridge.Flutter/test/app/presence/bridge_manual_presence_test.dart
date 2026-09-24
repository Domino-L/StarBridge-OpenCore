import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/bridge_manual_presence.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  const owner = BridgeAccountContext(
    environment: 'test',
    authority: 'presence.invalid',
    subject: 'sample',
  );
  for (final acknowledged in [true, false]) {
    test(
      'shared source consumes real Bridge confirmation=$acknowledged',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
        );
        final requests = <BridgeEnvelope>[];
        var revision = 'missing';
        var mode = 'online';
        final subscription = pair.host.incoming.listen((r) async {
          if (r.messageType != 'request') return;
          requests.add(r);
          if (r.name == 'presence.set') {
            mode = r.payload['mode']! as String;
            revision = 'A' * 64;
          }
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: r.name,
              sessionGeneration: r.sessionGeneration,
              correlationId: r.correlationId,
              accountContext: r.accountContext,
              status: 'ok',
              payload: {
                'schemaVersion': 1,
                'state': r.name == 'presence.set' && !acknowledged
                    ? 'unconfirmed'
                    : 'ready',
                'revision': revision,
                'mode': mode,
              },
            ),
          );
        });
        final account = ValueNotifier(
          const PresenceAccountScope(
            generation: 1,
            account: owner,
            available: true,
            automaticKey: 'presence.online',
          ),
        );
        final source = BridgeManualPresence(session, account);
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(source.value.selfKey, 'presence.online');
        await source.controller.select(PresenceVisibility.invisible);
        expect(
          source.value.confirmedMode,
          acknowledged ? PresenceVisibility.invisible : null,
        );
        expect(source.controller.failed, !acknowledged);
        expect(requests.map((r) => r.name), ['presence.read', 'presence.set']);
        expect(requests.last.payload['expectedRevision'], 'missing');
        expect(requests.last.accountContext!.subject, 'sample');
        account.value = const PresenceAccountScope(
          generation: 1,
          account: owner,
          available: true,
          automaticKey: 'presence.inGame',
        );
        expect(
          source.value.selfKey,
          acknowledged ? 'presence.invisible' : 'presence.unknown',
        );
        expect(requests.length, 2);
        account.value = const PresenceAccountScope(
          generation: 1,
          account: owner,
          available: false,
          automaticKey: 'presence.offline',
        );
        expect(
          source.value.selfKey,
          acknowledged ? 'presence.invisible' : 'presence.unknown',
        );
        expect(source.controller.canChange, false);
        source.dispose();
        account.dispose();
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      },
    );
  }
  test('missing capability never requests or enables writes', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    var calls = 0;
    final sub = pair.host.incoming.listen((_) => calls++);
    final account = ValueNotifier(
      const PresenceAccountScope(
        generation: 1,
        account: owner,
        available: false,
      ),
    );
    final source = BridgeManualPresence(session, account);
    await source.refresh();
    await source.controller.select(PresenceVisibility.invisible);
    expect(calls, 0);
    expect(source.controller.canChange, false);
    source.dispose();
    account.dispose();
    await sub.cancel();
    await session.close();
    await pair.host.close();
  });
  test('changed account cannot receive a pending old result', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final request = Completer<BridgeEnvelope>();
    final sub = pair.host.incoming.listen((r) {
      if (r.messageType == 'request' && !request.isCompleted) {
        request.complete(r);
      }
    });
    final account = ValueNotifier(
      const PresenceAccountScope(
        generation: 1,
        account: owner,
        available: true,
      ),
    );
    final source = BridgeManualPresence(session, account);
    final old = await request.future;
    account.value = const PresenceAccountScope(
      generation: 2,
      account: null,
      available: false,
    );
    await pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: old.name,
        sessionGeneration: 1,
        correlationId: old.correlationId,
        accountContext: owner,
        status: 'ok',
        payload: {
          'schemaVersion': 1,
          'state': 'ready',
          'revision': 'missing',
          'mode': 'invisible',
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(source.value.confirmedMode, null);
    expect(source.controller.canChange, false);
    source.dispose();
    account.dispose();
    await sub.cancel();
    await session.close();
    await pair.host.close();
  });
}
