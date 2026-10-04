import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_directory.dart';

void main() {
  test(
    'retiring menu scope cancels pending picker without retiring client page',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      final chooser = Completer<BridgeEnvelope>();
      final cancelled = Completer<BridgeEnvelope>();
      final subscription = pair.host.incoming.listen((request) async {
        if (request.name == 'bridge.cancel') {
          cancelled.complete(request);
        } else if (request.name.endsWith('.choose')) {
          chooser.complete(request);
        } else {
          await pair.host.send(
            _ok(request, const {
              'schemaVersion': 1,
              'revision': 0,
              'directory': r'C:\synthetic',
              'isDefault': true,
              'cancelled': false,
              'opened': false,
            }),
          );
        }
      });
      try {
        final client = BridgeMenuScreenshotDirectory(session);
        final scope = client.fork();
        final saved = await scope.read();
        final work = scope.choose(saved);
        final failed = expectLater(work, throwsA(isA<BridgeClientException>()));
        final started = await chooser.future;
        scope.dispose();
        await failed;
        final cancellation = await cancelled.future;
        expect(
          cancellation.payload['targetCorrelationId'],
          started.correlationId,
        );
        expect(scope.fork, throwsA(isA<BridgeClientException>()));
        expect((await client.read()).directory, r'C:\synthetic');
        final reopened = client.fork();
        expect((await reopened.read()).revision, 0);
        reopened.dispose();
        client.dispose();
      } finally {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    },
  );
  const path = r'C:\synthetic\screenshots';
  const valid = {
    'schemaVersion': 1,
    'revision': 1,
    'directory': path,
    'isDefault': false,
    'cancelled': false,
    'opened': false,
  };
  test('destination reply is strict and never defaults on malformed data', () {
    expect(MenuScreenshotDirectory.parse(valid).directory, path);
    expect(
      MenuScreenshotDirectory.parse({
        ...valid,
        'directory': r'\\server.invalid\synthetic-share\screenshots',
      }).directory,
      r'\\server.invalid\synthetic-share\screenshots',
    );
    for (final bad in [
      null,
      {},
      {...valid, 'revision': -1},
      {...valid, 'revision': 1.5},
      {...valid, 'schemaVersion': 2},
      {...valid, 'directory': null},
      {...valid, 'directory': ''},
      {...valid, 'directory': 'relative'},
      {...valid, 'directory': r'C:relative'},
      {...valid, 'directory': r'\\?\C:\synthetic'},
      {...valid, 'directory': r'C:\synthetic\..\elsewhere'},
      {...valid, 'directory': '$path\n'},
      {...valid, 'directory': '$path '},
      {...valid, 'directory': 'x' * 32768},
      {...valid, 'isDefault': 'false'},
      {...valid, 'cancelled': 0},
      {...valid, 'opened': 'true'},
      {...valid, 'cancelled': true, 'opened': true},
      {...valid, 'owner': 'forbidden'},
      {...valid}..remove('directory'),
      {...valid}..remove('cancelled'),
    ]) {
      expect(() => MenuScreenshotDirectory.parse(bad), throwsFormatException);
    }
  });

  test(
    'every intent sends only schema/revision, never a path or account',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      final requests = <BridgeEnvelope>[];
      Map<String, Object?> reply = valid;
      final subscription = pair.host.incoming.listen((request) async {
        requests.add(request);
        await pair.host.send(_ok(request, reply));
      });
      try {
        final port = BridgeMenuScreenshotDirectory(session);
        final saved = await port.read();
        expect(requests.single.payload, {'schemaVersion': 1});
        await port.choose(saved);
        await port.reset(saved);
        reply = {...valid, 'opened': true};
        expect((await port.open(saved)).opened, true);
        expect(requests.map((r) => r.name), [
          'menuScreenshotDirectory.read',
          'menuScreenshotDirectory.choose',
          'menuScreenshotDirectory.reset',
          'menuScreenshotDirectory.open',
        ]);
        for (final request in requests.skip(1)) {
          expect(request.payload, {'schemaVersion': 1, 'expectedRevision': 1});
        }
        for (final request in requests) {
          expect(request.accountContext, isNull);
          expect(request.sessionGeneration, 7);
        }
        reply = {...valid, 'cancelled': true};
        expect((await port.choose(saved)).cancelled, true);
        await expectLater(port.read(), throwsFormatException);
        reply = {...valid, 'opened': true};
        await expectLater(port.choose(saved), throwsFormatException);
        reply = {...valid, 'revision': 0};
        await expectLater(port.reset(saved), throwsFormatException);
        reply = {...valid, 'opened': true, 'directory': r'C:\unexpected'};
        await expectLater(port.open(saved), throwsFormatException);
      } finally {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    },
  );

  test(
    'late chooser reply and old port cannot cross account transition',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      final received = Completer<BridgeEnvelope>();
      var calls = 0;
      final subscription = pair.host.incoming.listen((request) {
        calls++;
        if (!received.isCompleted) received.complete(request);
      });
      try {
        final port = BridgeMenuScreenshotDirectory(session);
        final saved = MenuScreenshotDirectory.parse(valid);
        final pending = port.choose(saved);
        final failed = expectLater(
          pending,
          throwsA(isA<BridgeClientException>()),
        );
        final request = await received.future;
        session.advanceGeneration(8);
        await failed;
        await pair.host.send(_ok(request, valid));
        final before = calls;
        for (final action in [
          port.read,
          () => port.choose(saved),
          () => port.open(saved),
          () => port.reset(saved),
        ]) {
          await expectLater(action(), throwsA(isA<BridgeClientException>()));
        }
        expect(calls, before);
        expect(port.fork, throwsA(isA<BridgeClientException>()));
      } finally {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    },
  );
}

BridgeEnvelope _ok(BridgeEnvelope request, Map<String, Object?> payload) =>
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      payload: payload,
      status: 'ok',
    );
