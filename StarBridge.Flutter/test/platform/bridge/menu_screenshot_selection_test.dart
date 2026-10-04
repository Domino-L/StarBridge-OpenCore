import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_directory.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  const path = r'C:\synthetic';
  const snapshot = MenuScreenshotDirectory(
    revision: 2,
    directory: path,
    isDefault: true,
  );
  const selection = {
    'schemaVersion': 1,
    'revision': 2,
    'directory': path,
    'token': token,
    'cancelled': false,
  };
  test(
    'selection strictly validates native-only token and displayed directory',
    () {
      expect(MenuScreenshotDirectorySelection.parse(selection).token, token);
      expect(
        MenuScreenshotDirectorySelection.parse({
          ...selection,
          'cancelled': true,
          'token': null,
        }).cancelled,
        true,
      );
      for (final bad in [
        {...selection, 'token': null},
        {...selection, 'token': 'invented'},
        {...selection, 'cancelled': true},
        {...selection, 'directory': 'relative'},
        {...selection, 'directory': r'C:\synthetic\..\elsewhere'},
        {...selection, 'revision': -1},
        {...selection, 'owner': 'forbidden'},
        {...selection}..remove('schemaVersion'),
      ]) {
        expect(
          () => MenuScreenshotDirectorySelection.parse(bad),
          throwsFormatException,
        );
      }
    },
  );
  test('folder choice stays draft until explicit token commit; no renderer path is sent', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
    );
    final requests = <BridgeEnvelope>[];
    final subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'ok',
          payload: request.name.endsWith('.chooseDraft')
              ? selection
              : const {
                  'schemaVersion': 1,
                  'revision': 3,
                  'directory': path,
                  'isDefault': false,
                  'cancelled': false,
                  'opened': false,
                },
        ),
      );
    });
    try {
      final port = BridgeMenuScreenshotDirectory(session);
      final draft = await port.chooseDraft(snapshot);
      expect(requests.single.name, 'menuScreenshotDirectory.chooseDraft');
      expect(requests.single.payload, {
        'schemaVersion': 1,
        'expectedRevision': 2,
      });
      expect(requests.single.accountContext, isNull);
      expect((await port.commitDraft(draft)).revision, 3);
      expect(requests.last.payload, {
        'schemaVersion': 1,
        'expectedRevision': 2,
        'token': token,
      });
      expect(requests.every((r) => !r.payload.containsKey('directory')), true);
      session.advanceGeneration(5);
      await expectLater(
        port.commitDraft(draft),
        throwsA(isA<BridgeClientException>()),
      );
      expect(requests.length, 2);
      port.dispose();
    } finally {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    }
  });
}
