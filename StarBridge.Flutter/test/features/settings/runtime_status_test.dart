import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/bridge_runtime_facts.dart';
import 'package:starbridge_flutter/features/settings/bridge_runtime_overlay_status.dart';
import 'package:starbridge_flutter/features/settings/runtime_status_entry.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/features/settings/runtime_status_controller.dart';
import 'package:starbridge_flutter/features/settings/runtime_status_dialog.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

const _installation = RuntimeInstallationFacts(
  dataDirectory: r'C:\Synthetic\Data',
  imageCacheDirectory: r'C:\Synthetic\Data\Images',
  imageCacheExists: false,
  applicationVersion: '0.1.0+1',
);
const _overlay = RuntimeOverlayFacts(
  windowState: 'closed',
  hotkeyBinding: 'Alt+F10',
  hotkeyState: 'conflict',
  presetName: 'Default',
);
const _startup = RuntimeStartupFacts(
  launchAtStartup: true,
  startMinimized: true,
  keepRunningInBackground: false,
);

void main() {
  testWidgets(
    'global shortcut degradation is explicit rather than a feature restriction',
    (tester) async {
      final controller = _controller(
        overlay: () async => const RuntimeOverlayFacts(
          windowState: 'closed',
          hotkeyBinding: 'Alt+O',
          hotkeyState: 'gameCompatibleOnly',
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('全局快捷键'), findsOneWidget);
      expect(find.textContaining('全局快捷键未能启用，游戏内仍可使用'), findsOneWidget);
      expect(find.textContaining('仅游戏内可用'), findsNothing);
      final field = tester.widget<SelectableText>(
        find.descendant(
          of: find.byKey(const Key('runtime-status-hotkey')),
          matching: find.byType(SelectableText),
        ),
      );
      expect(field.style?.color, isNotNull);
    },
  );
  test(
    'overlay snapshot uses dedicated accountless read, not mutating getState',
    () async {
      final connection = _Connection()..payload.clear();
      connection.payload.addAll({
        'schemaVersion': 1,
        'windowState': 'open',
        'hotkeyState': 'registered',
        'hotkeyBinding': 'Alt+F10',
        'appliedRevision': 7,
      });
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 2,
      );
      addTearDown(session.close);
      final result = await BridgeRuntimeOverlayStatus(session).read();
      expect(result.windowState, 'open');
      expect(
        connection.sent.single.name,
        'diagnostics.getOverlayRuntimeStatus',
      );
      expect(connection.sent.single.payload, {'schemaVersion': 1});
      expect(connection.sent.single.accountContext, isNull);
      connection.payload['windowState'] = 'invented';
      await expectLater(
        BridgeRuntimeOverlayStatus(session).read(),
        throwsFormatException,
      );
      connection.payload['windowState'] = 'closed';
      connection.payload['workspace'] = {'preview': 'private'};
      await expectLater(
        BridgeRuntimeOverlayStatus(session).read(),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'connected opener with missing capabilities keeps entry without sending requests',
    (tester) async {
      final controller = _controller();
      final preferences = InMemoryAppPreferences();
      final connection = _Connection();
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 2,
      );
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        _app(
          controller,
          open: (context) => showConnectedRuntimeStatus(
            context,
            preferences: preferences,
            session: session,
            metadataAvailable: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(RuntimeStatusDialog), findsOneWidget);
      expect(connection.sent, isEmpty);
      await tester.tap(find.byKey(const Key('runtime-status-close')));
      await tester.pumpAndSettle();
      // Closing the dialog does not close borrowed preferences or Bridge.
      expect(preferences.projection.value.confirmed, isNotNull);
      await tester.runAsync(() async {
        await BridgeRuntimeFacts(session).read();
        await session.close();
      });
      expect(connection.sent.single.name, 'diagnostics.getRuntimeFacts');
    },
  );
  test(
    'reads three sources concurrently, coalesces refresh, clears stale values',
    () async {
      var reads = 0;
      Completer<RuntimeInstallationFacts?>? pending;
      final controller = _controller(
        installation: () {
          reads++;
          return pending?.future ?? Future.value(_installation);
        },
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.value.incomplete, isFalse);
      pending = Completer();
      final refresh = controller.refresh();
      expect(controller.value.busy, isTrue);
      expect(controller.value.installation, isNull);
      await controller.refresh();
      expect(reads, 2);
      pending.complete(null);
      await refresh;
      expect(controller.value.incomplete, isTrue);
      expect(controller.value.overlay!.hotkeyState, 'conflict');
      expect(controller.value.startup, same(_startup));
    },
  );

  test(
    'source failures preserve other facts and never surface raw errors',
    () async {
      final controller = _controller(
        overlay: () => throw StateError('private secret'),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.value.installation, same(_installation));
      expect(controller.value.overlay, isNull);
      expect(controller.value.incomplete, isTrue);
    },
  );

  test(
    'a stalled source times out without hiding successful sources',
    () async {
      final controller = _controller(
        overlay: () => Completer<RuntimeOverlayFacts?>().future,
        timeout: const Duration(milliseconds: 5),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.value.busy, isFalse);
      expect(controller.value.incomplete, isTrue);
      expect(controller.value.installation, same(_installation));
    },
  );

  test('dispose ignores late read and prevents later reads', () async {
    final pending = Completer<RuntimeInstallationFacts?>();
    var reads = 0, changes = 0;
    final controller = _controller(
      installation: () {
        reads++;
        return pending.future;
      },
    );
    controller.addListener(() => changes++);
    final reading = controller.refresh();
    controller.dispose();
    pending.complete(_installation);
    await reading;
    await controller.refresh();
    expect(reads, 1);
    expect(changes, 1);
  });

  test(
    'facts request is accountless and read-only; nullable metadata is valid',
    () async {
      final connection = _Connection();
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 2,
      );
      addTearDown(session.close);
      final facts = await BridgeRuntimeFacts(session).read();
      expect(facts.applicationVersion, isNull);
      expect(facts.serverOrigin, isNull);
      expect(facts.dataDirectory, r'C:\Synthetic\Data');
      expect(connection.sent, hasLength(1));
      expect(connection.sent.single.name, 'diagnostics.getRuntimeFacts');
      expect(connection.sent.single.accountContext, isNull);
      expect(connection.sent.single.payload, {'schemaVersion': 1});
    },
  );

  final invalid = <String, void Function(Map<String, Object?>)>{
    'wrong schema': (p) => p['schemaVersion'] = 2,
    'extra secret': (p) => p['token'] = 'private',
    'missing nullable key': (p) => p.remove('serverOrigin'),
    'relative data path': (p) => p['dataDirectory'] = 'Data',
    'control in cache path': (p) =>
        p['imageCacheDirectory'] = 'C:\\Data\nsecret',
    'wrong exists type': (p) => p['imageCacheExists'] = 'true',
    'version prose': (p) => p['applicationVersion'] = 'release private',
    'origin credentials': (p) =>
        p['serverOrigin'] = 'https://user:secret@example.com',
    'origin query': (p) =>
        p['serverOrigin'] = 'https://example.test?token=secret',
    'origin path': (p) => p['serverOrigin'] = 'https://example.test/private',
    'origin fragment': (p) => p['serverOrigin'] = 'https://example.test#secret',
    'origin local file': (p) => p['serverOrigin'] = 'file:///C:/secret',
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key}', () async {
      final connection = _Connection();
      entry.value(connection.payload);
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 2,
      );
      addTearDown(session.close);
      await expectLater(
        BridgeRuntimeFacts(session).read(),
        throwsFormatException,
      );
    });
  }

  test('accepts validated installed build and safe origin', () async {
    final connection = _Connection()
      ..payload.addAll({
        'applicationVersion': '1.2.3-beta+4',
        'serverOrigin': 'http://127.0.0.1:8080',
      });
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 2,
    );
    addTearDown(session.close);
    final value = await BridgeRuntimeFacts(session).read();
    expect(value.applicationVersion, '1.2.3-beta+4');
    expect(value.serverOrigin, 'http://127.0.0.1:8080');
  });

  testWidgets(
    'overview separates technical details and omits duplicate preferences',
    (tester) async {
      var reads = 0;
      final controller = _controller(
        installation: () async {
          reads++;
          return _installation;
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      for (final key in ['overlay', 'hotkey']) {
        expect(find.byKey(Key('runtime-status-$key')), findsOneWidget);
      }
      for (final key in [
        'mode',
        'startup',
        'data',
        'images',
        'version',
        'server',
      ]) {
        expect(find.byKey(Key('runtime-status-$key')), findsNothing);
      }
      await tester.tap(find.byKey(const Key('runtime-status-details')));
      await tester.pumpAndSettle();
      for (final key in ['data', 'images', 'version', 'server']) {
        expect(find.byKey(Key('runtime-status-$key')), findsOneWidget);
      }
      expect(find.text('未显示'), findsOneWidget);
      expect(find.textContaining('被其他应用占用'), findsOneWidget);
      expect(find.textContaining('0.1.0+1'), findsOneWidget);
      expect(reads, 1);
      await tester.tap(find.byKey(const Key('runtime-status-refresh')));
      await tester.pumpAndSettle();
      expect(reads, 2);
      await tester.tap(find.byKey(const Key('runtime-status-close')));
      await tester.pumpAndSettle();
      expect(find.byType(RuntimeStatusDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading can be closed; late response does not reopen dialog', (
    tester,
  ) async {
    final pending = Completer<RuntimeInstallationFacts?>();
    final controller = _controller(installation: () => pending.future);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('runtime-status-refresh')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('runtime-status-close')));
    await tester.pump(const Duration(milliseconds: 300));
    controller.dispose();
    pending.complete(_installation);
    await tester.pumpAndSettle();
    expect(find.byType(RuntimeStatusDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets(
        'narrow real dialog wraps long paths and errors: $locale $mode',
        (tester) async {
          tester.view.physicalSize = const Size(390, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = _controller(
            installation: () async => RuntimeInstallationFacts(
              dataDirectory: 'C:\\${'LongFolder' * 40}',
              imageCacheDirectory: r'C:\Synthetic\Images',
              imageCacheExists: false,
            ),
            overlay: () => throw StateError('private secret'),
          );
          addTearDown(controller.dispose);
          await tester.pumpWidget(_app(controller, locale: locale, mode: mode));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('runtime-status-partial')),
            findsOneWidget,
          );
          expect(find.textContaining('private secret'), findsNothing);
          await tester.tap(find.byKey(const Key('runtime-status-details')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('runtime-status-server')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('runtime-status-close')));
          await tester.pumpAndSettle();
        },
      );
    }
  }
}

RuntimeStatusController _controller({
  Future<RuntimeInstallationFacts?> Function()? installation,
  Future<RuntimeOverlayFacts?> Function()? overlay,
  Duration timeout = const Duration(seconds: 15),
}) => RuntimeStatusController(
  readInstallation: installation ?? () async => _installation,
  readOverlay: overlay ?? () async => _overlay,
  readStartup: () async => _startup,
  sourceTimeout: timeout,
);

Widget _app(
  RuntimeStatusController controller, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
  Future<void> Function(BuildContext)? open,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.runtimeSupportedLocales(),
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildStarBridgeTheme(
    StyleRegistry().resolve(AppPreferences.defaults.designStyleId, mode).tokens,
    locale,
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => open != null
            ? open(context)
            : showRuntimeStatusDialog(context, controller),
        child: const Text('Open'),
      ),
    ),
  ),
);

class _Connection implements BridgeConnection {
  final _incoming = StreamController<BridgeEnvelope>();
  final List<BridgeEnvelope> sent = [];
  final payload = <String, Object?>{
    'schemaVersion': 1,
    'applicationVersion': null,
    'dataDirectory': r'C:\Synthetic\Data',
    'imageCacheDirectory': r'C:\Synthetic\Data\Images',
    'imageCacheExists': false,
    'serverOrigin': null,
  };
  @override
  Stream<BridgeEnvelope> get incoming => _incoming.stream;
  @override
  Future<void> send(BridgeEnvelope request) async {
    sent.add(request);
    _incoming.add(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        status: 'ok',
        payload: Map.of(payload),
      ),
    );
  }

  @override
  Future<void> close() => _incoming.close();
}
