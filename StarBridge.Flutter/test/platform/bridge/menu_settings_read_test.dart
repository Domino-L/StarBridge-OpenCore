import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_settings_read.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_resume.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_directory.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

class Fixture {
  Fixture() {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    subscription = pair.host.incoming.listen((request) {
      if (request.name == 'bridge.cancel') return;
      requests.add(request);
      onRequest?.call(request);
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  void Function(BridgeEnvelope)? onRequest;
  void reply(
    BridgeEnvelope request, {
    Map<String, Object?> payload = const {},
    String? error,
    bool retryable = true,
  }) {
    unawaited(
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: error == null ? 'ok' : 'error',
          payload: payload,
          error: error == null
              ? null
              : BridgeErrorBody(
                  code: error,
                  message: 'synthetic',
                  retryable: retryable,
                ),
        ),
      ),
    );
  }

  void close() {
    unawaited(subscription.cancel());
    unawaited(session.close());
    unawaited(pair.host.close());
  }
}

void main() {
  testWidgets('normal Bridge deadline remains bounded without timeout retry', (
    tester,
  ) async {
    final f = Fixture();
    addTearDown(f.close);
    final failed = expectLater(
      readMenuSettings(f.session, 'applicationPreferences.menu.get'),
      throwsA(isA<BridgeTimeoutException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    await failed;
    await tester.pump(const Duration(seconds: 20));
    expect(f.requests, hasLength(1));
  });
  test('nonretryable busy reply is not replayed', () async {
    final f = Fixture();
    addTearDown(f.close);
    f.onRequest = (r) =>
        f.reply(r, error: 'bridge.backpressure', retryable: false);
    await expectLater(
      readMenuSettings(f.session, 'applicationPreferences.menu.get'),
      throwsA(isA<BridgeRemoteException>()),
    );
    expect(f.requests, hasLength(1));
  });
  testWidgets(
    'explicit transient rejection retries once without caching or writing',
    (tester) async {
      final f = Fixture();
      addTearDown(f.close);
      f.onRequest = (r) => f.reply(
        r,
        error: f.requests.length == 1 ? 'bridge.backpressure' : null,
      );
      var completed = false;
      final future = readMenuSettings(
        f.session,
        'applicationPreferences.menu.get',
      ).then((_) => completed = true);
      await tester.pump();
      expect(completed, false);
      await tester.pump(const Duration(milliseconds: 250));
      await future;
      expect(f.requests, hasLength(2));
      await readMenuSettings(f.session, 'applicationPreferences.menu.get');
      expect(f.requests, hasLength(3));
    },
  );
  testWidgets('persistent busy is bounded to two attempts', (tester) async {
    final f = Fixture();
    addTearDown(f.close);
    f.onRequest = (r) => f.reply(r, error: 'bridge.backpressure');
    final failed = expectLater(
      readMenuSettings(f.session, 'applicationPreferences.menu.get'),
      throwsA(isA<BridgeRemoteException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await failed;
    expect(f.requests, hasLength(2));
    await tester.pump(const Duration(seconds: 30));
    expect(f.requests, hasLength(2));
  });
  for (final error in [
    'bridge.stale_generation',
    'account.unauthorized',
    'menuPreferences.revision_conflict',
  ]) {
    test(
      'authority and conflict errors never retry even when flagged retryable: $error',
      () async {
        final f = Fixture();
        addTearDown(f.close);
        f.onRequest = (r) => f.reply(r, error: error);
        await expectLater(
          readMenuSettings(f.session, 'applicationPreferences.menu.get'),
          throwsA(isA<BridgeRemoteException>()),
        );
        expect(f.requests, hasLength(1));
      },
    );
  }
  testWidgets(
    'generation change during retry delay stops before second request',
    (tester) async {
      final f = Fixture();
      addTearDown(f.close);
      f.onRequest = (r) => f.reply(r, error: 'bridge.backpressure');
      final failed = expectLater(
        readMenuSettings(f.session, 'applicationPreferences.menu.get'),
        throwsA(isA<BridgeStaleGenerationException>()),
      );
      await tester.pump();
      f.session.advanceGeneration(2);
      await tester.pump(const Duration(milliseconds: 250));
      await failed;
      expect(f.requests, hasLength(1));
    },
  );
  testWidgets('disposed screenshot owner stops delayed retry', (tester) async {
    final f = Fixture();
    addTearDown(f.close);
    final port = BridgeMenuScreenshotDirectory(f.session);
    f.onRequest = (r) => f.reply(r, error: 'bridge.backpressure');
    final failed = expectLater(
      port.read(),
      throwsA(isA<BridgeClientException>()),
    );
    await tester.pump();
    port.dispose();
    await tester.pump(const Duration(milliseconds: 250));
    await failed;
    expect(f.requests, hasLength(1));
  });
  test(
    'read helper refuses writes and parser failures are not retried',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      await expectLater(
        readMenuSettings(f.session, 'applicationPreferences.menu.update'),
        throwsArgumentError,
      );
      expect(f.requests, isEmpty);
      f.onRequest = (r) => f.reply(r);
      await expectLater(
        BridgeMenuWindowPreferences(f.session).read(),
        throwsFormatException,
      );
      expect(f.requests, hasLength(1));
      f.onRequest = (r) => f.reply(r, error: 'bridge.backpressure');
      await expectLater(
        BridgeMenuWindowPreferences(f.session)
            .save(MenuWindowPreferences.defaults),
        throwsA(isA<BridgeRemoteException>()),
      );
      expect(f.requests, hasLength(2));
    },
  );
  for (final kind in ['browser', 'directory']) {
    testWidgets('$kind metadata accepts first reply after three seconds', (
      tester,
    ) async {
      final f = Fixture();
      addTearDown(f.close);
      Timer? timer;
      addTearDown(() => timer?.cancel());
      f.onRequest = (r) {
        timer = Timer(
          const Duration(milliseconds: 3200),
          () => f.reply(
            r,
            payload: kind == 'browser'
                ? const {
                    'schemaVersion': 1,
                    'revision': 0,
                    'enabled': false,
                    'url': null,
                  }
                : const MenuScreenshotDirectory(
                    revision: 0,
                    directory: r'C:\Synthetic\Screenshots',
                    isDefault: true,
                  ).toMap(),
          ),
        );
      };
      var done = false;
      final future =
          (kind == 'browser'
                  ? BridgeMenuBrowserResume(f.session).read()
                  : BridgeMenuScreenshotDirectory(f.session).read())
              .then((_) => done = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3200));
      await future;
      expect(done, true);
      expect(f.requests, hasLength(1));
    });
  }
}
