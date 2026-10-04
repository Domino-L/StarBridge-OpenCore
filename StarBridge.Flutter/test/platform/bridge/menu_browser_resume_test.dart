import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_resume.dart';

void main() {
  const address = 'https://example.invalid/?q=synthetic#section';
  const valid = {
    'schemaVersion': 1,
    'revision': 1,
    'enabled': true,
    'url': address,
  };
  test(
    'strict account-local resume reply never accepts missing or unsafe data',
    () {
      expect(MenuBrowserResume.parse(valid).url, address);
      expect(
        MenuBrowserResume.parse({...valid, 'enabled': false, 'url': null})
            .enabled,
        false,
      );
      for (final raw in [
        null,
        {},
        {...valid, 'owner': 'forbidden'},
        {...valid, 'revision': 1.5},
        {...valid, 'revision': -1},
        {...valid, 'enabled': 'true'},
        {...valid, 'enabled': false},
        {...valid, 'schemaVersion': 2},
        {...valid}..remove('url'),
        for (final url in [
          'javascript:alert(1)',
          'file:///C:/',
          'data:text/plain,test',
          'starbridge://account',
          'https://user:password@example.invalid/',
          ' https://example.invalid/',
          'https://example.invalid/\n',
          'https://example.invalid/\\unsafe',
          '',
          'http:///',
        ])
          {...valid, 'url': url},
      ]) {
        expect(() => MenuBrowserResume.parse(raw), throwsFormatException);
      }
    },
  );
  test('bridge uses current Host-derived owner; no local files, paths or credentials', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 7,
    );
    final requests = <BridgeEnvelope>[];
    Map<String, Object?> reply = {
      'schemaVersion': 1,
      'revision': 0,
      'enabled': false,
      'url': null,
    };
    final subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          payload: reply,
          status: 'ok',
        ),
      );
    });
    try {
      final bridge = BridgeMenuBrowserResume(session);
      final disabled = await bridge.read();
      expect(disabled.enabled, false);
      expect(requests.single.payload, {'schemaVersion': 1});
      expect(() => bridge.remember(disabled, address), throwsFormatException);
      expect(requests.length, 1);
      reply = valid;
      final enabled = await bridge.setEnabled(disabled, true);
      expect(requests.last.payload, {
        'schemaVersion': 1,
        'expectedRevision': 0,
        'enabled': true,
      });
      expect(enabled.url, address);
      await bridge.remember(enabled, address);
      expect(requests.last.payload, {
        'schemaVersion': 1,
        'expectedRevision': 1,
        'url': address,
      });
      for (final request in requests) {
        expect(request.accountContext, isNull);
        expect(request.sessionGeneration, 7);
      }
      reply = {...valid}..remove('url');
      await expectLater(bridge.read(), throwsFormatException);
    } finally {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    }
  });
  test(
    'pending account reply cannot become valid after generation changes',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen(requests.add);
      try {
        final bridge = BridgeMenuBrowserResume(session);
        final pending = bridge.read();
        final failure = expectLater(
          pending,
          throwsA(isA<BridgeClientException>()),
        );
        await Future<void>.delayed(Duration.zero);
        session.advanceGeneration(8);
        await failure;
        final request = requests.first;
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: 7,
            payload: valid,
            status: 'ok',
          ),
        );
        expect(session.activeGeneration, 8);
        final count = requests.length;
        await expectLater(bridge.read(), throwsA(isA<BridgeClientException>()));
        await expectLater(
          bridge.remember(MenuBrowserResume.parse(valid), address),
          throwsA(isA<BridgeClientException>()),
        );
        expect(requests.length, count);
      } finally {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    },
  );
}
