import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/routing/exit_application_intent.dart';
import 'package:starbridge_flutter/app/runtime/application_update_flow.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/features/settings/application_update_dialog.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );
  final heroNotes =
      '# 新版本\n- 【一】a\n- 【二】b\n- 【三】c\n'
      '主图校验 sha256=${sha256.convert(png)} bytes=${png.length}';
  Map<String, dynamic> heroChunk(int offset, int end) => {
    'schemaVersion': 1,
    'version': '0.7.4',
    'mediaType': 'image/png',
    'sha256': sha256.convert(png).toString(),
    'length': png.length,
    'offset': offset,
    'nextOffset': end,
    'chunk': base64Encode(png.sublist(offset, end)),
    'done': end == png.length,
  };

  testWidgets(
    'manual check carries manual provenance through every hero chunk',
    (tester) async {
      final h = Harness()
        ..version = '0.7.4'
        ..notes = heroNotes
        ..heroEnabled = true;
      await h.mount(tester, automatic: false);
      expect(h.automaticFlags, [null]);
      expect(h.pendingHero!.payload['automatic'], isFalse);
      h.reply(h.pendingHero!, heroChunk(0, 32));
      await tester.pump();
      expect(h.pendingHero!.payload['offset'], 32);
      expect(h.pendingHero!.payload['automatic'], isFalse);
      h.reply(h.pendingHero!, heroChunk(32, png.length));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-hero-image')), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-install')), findsOneWidget);
      await h.close(tester);
    },
  );
  testWidgets('slow mirrored hero survives the old 30 second bridge limit', (
    tester,
  ) async {
    final h = Harness()
      ..version = '0.7.4'
      ..notes = heroNotes
      ..heroEnabled = true;
    await h.mount(tester);
    expect(h.pendingHero, isNotNull);
    expect(h.pendingHero!.payload['automatic'], isTrue);
    await tester.pump(const Duration(seconds: 31));
    h.reply(h.pendingHero!, heroChunk(0, png.length));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('update-hero-image')), findsOneWidget);
    expect(find.byKey(const Key('update-download')), findsOneWidget);
    await h.close(tester);
  });

  testWidgets(
    'hero total timeout includes chunks and never delays preparation',
    (tester) async {
      final h = Harness()
        ..version = '0.7.4'
        ..notes = heroNotes
        ..heroEnabled = true;
      await h.mount(tester);
      await tester.pump(const Duration(seconds: 20));
      h.reply(h.pendingHero!, heroChunk(0, 32));
      await tester.pump();
      final second = h.pendingHero!;
      expect(second.payload['offset'], 32);
      expect(second.payload['automatic'], isTrue);
      await tester.tap(find.byKey(const Key('update-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-install')), findsOneWidget);
      // The second chunk gets only the remainder of the overall 35 seconds.
      await tester.pump(const Duration(seconds: 16));
      expect(h.cancelled, contains(second.correlationId));
      h.reply(second, heroChunk(32, png.length));
      await tester.pump();
      expect(find.byKey(const Key('update-hero-image')), findsNothing);
      expect(find.byKey(const Key('update-install')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );

  testWidgets(
    'entry silently checks once then opens the installable secondary announcement',
    (tester) async {
      final h = Harness()..ready = false;
      await h.mount(tester);
      expect(h.requests, isEmpty);
      h.ready = true;
      h.flow.wake();
      await tester.pumpAndSettle();
      expect(h.requests, ['applicationUpdates.check']);
      expect(h.automaticFlags, [true]);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('更新并重启'), findsOneWidget);
      expect(find.text('优化'), findsOneWidget);
      expect(find.textContaining('##'), findsNothing);
      expect(find.text('稍后'), findsOneWidget);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      h.flow.wake();
      h.reconnectFlow();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('application-update-dialog')), findsNothing);
      expect(h.shown, {'0.7.0.2'});
      expect(h.requests.where((r) => r != 'applicationUpdates.check'), isEmpty);
      await h.close(tester);
    },
  );
  for (final state in [
    'up-to-date',
    'verification-failed',
    'configuration-invalid',
    'channel-unconfigured',
  ]) {
    testWidgets('$state stays silent and never installs', (tester) async {
      final h = Harness()..state = state;
      await h.mount(tester);
      expect(find.byKey(const Key('application-update-dialog')), findsNothing);
      expect(h.requests, ['applicationUpdates.check']);
      await h.close(tester);
    });
  }
  testWidgets('consent and manual dialogs finish before queued announcement', (
    tester,
  ) async {
    final h = Harness()..present = false;
    await h.mount(tester);
    expect(h.requests, ['applicationUpdates.check']);
    expect(find.text('发现新版本'), findsNothing);
    final nav = h.queue.navigator!;
    unawaited(
      showDialog<void>(
        context: nav.context,
        builder: (_) => const AlertDialog(title: Text('manual')),
      ),
    );
    h.present = true;
    h.queue.wake();
    await tester.pumpAndSettle();
    expect(find.text('manual'), findsOneWidget);
    expect(find.text('发现新版本'), findsNothing);
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    await h.close(tester);
  });
  testWidgets(
    'a manually seen version does not produce a second automatic dialog',
    (tester) async {
      final h = Harness()..present = false;
      await h.mount(tester);
      applicationUpdateShownVersions(h.session).add('0.7.0.2');
      h.present = true;
      h.queue.wake();
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsNothing);
      await h.close(tester);
      expect(h.shown, {'0.7.0.2'});
    },
  );
  testWidgets(
    'temporary failure retries silently and stops after three reads',
    (tester) async {
      final h = Harness()..state = 'channel-unavailable';
      await h.mount(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 1));
      expect(h.requests, hasLength(3));
      expect(find.byKey(const Key('application-update-dialog')), findsNothing);
      await h.close(tester);
    },
  );
  testWidgets('malformed offers remain silent', (tester) async {
    final h = Harness()..version = 'not-a-version';
    await h.mount(tester);
    expect(find.text('发现新版本'), findsNothing);
    expect(h.shown, isEmpty);
    await h.close(tester);
  });
  testWidgets('host disposal dismisses its announcement without installing', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester);
    h.flow.dispose();
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsNothing);
    expect(h.requests, ['applicationUpdates.check']);
    await h.close(tester);
  });
  testWidgets('disposed check ignores a late offer', (tester) async {
    final h = Harness()..hold = true;
    await h.mount(tester);
    h.flow.dispose();
    h.respond(h.pending!);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsNothing);
    await h.close(tester);
  });
}

class Harness {
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 1,
  );
  final queue = StartupPromptQueue(quietPeriod: Duration.zero);
  final shown = <String>{};
  final requests = <String>[];
  final automaticFlags = <Object?>[];
  final cancelled = <String>[];
  bool heroEnabled = false;
  String notes = '## 优化\n- 桌面图标与共享设置';
  bool ready = true, present = true, hold = false;
  String state = 'available', version = '0.7.0.2';
  BridgeEnvelope? pending;
  BridgeEnvelope? pendingHero;
  late ApplicationUpdateFlow flow;
  late StreamSubscription<BridgeEnvelope> subscription;
  void reply(BridgeEnvelope request, Map<String, dynamic> payload) {
    unawaited(
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: 1,
          status: 'ok',
          payload: payload,
        ),
      ),
    );
  }

  void respond(BridgeEnvelope request) => reply(request, {
    'schemaVersion': 1,
    'state': state,
    'currentVersion': '0.7.0.1',
    'availableVersion': state == 'available' ? version : null,
    'notes': state == 'available' ? notes : null,
  });

  void createFlow() => flow = ApplicationUpdateFlow(
    session: session,
    queue: queue,
    ready: () => ready,
    canPresent: () => present,
    shownVersions: shown,
  );
  void reconnectFlow() {
    flow.dispose();
    createFlow();
    flow.wake();
  }

  Future<void> mount(WidgetTester tester, {bool automatic = true}) async {
    session.acceptHostCapabilities([
      'applicationUpdates.check',
      'applicationUpdates.prepare',
      'applicationUpdates.handoff',
      if (heroEnabled) 'applicationUpdates.heroRead',
    ]);
    subscription = pair.host.incoming.listen((request) {
      if (request.messageType != 'request') return;
      if (request.name == 'bridge.cancel') {
        cancelled.add(request.payload['targetCorrelationId'] as String);
        return;
      }
      requests.add(request.name);
      if (request.name == 'applicationUpdates.check') {
        automaticFlags.add(request.payload['automatic']);
      }
      if (request.name == 'applicationUpdates.heroRead') {
        pendingHero = request;
        return;
      }
      if (request.name == 'applicationUpdates.prepare') {
        reply(request, {
          'schemaVersion': 1,
          'version': version,
          'ticket': 'a' * 32,
        });
        return;
      }
      pending = request;
      if (!hold) respond(request);
    });
    createFlow();
    await tester.pumpWidget(
      Actions(
        actions: {
          ExitApplicationIntent: CallbackAction<ExitApplicationIntent>(
            onInvoke: (_) => null,
          ),
        },
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          navigatorObservers: [queue],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showApplicationUpdateDialog(context, session),
                child: const Text('manual-update'),
              ),
            ),
          ),
        ),
      ),
    );
    if (automatic) {
      flow.wake();
    } else {
      await tester.pumpAndSettle();
      await tester.tap(find.text('manual-update'));
    }
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    flow.dispose();
    await tester.pumpAndSettle();
    queue.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
  }
}
