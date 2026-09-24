import 'dart:async';

import 'package:flutter/material.dart' hide LocalHistoryEntry;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/local_event_clear.dart';
import 'package:starbridge_flutter/features/settings/local_event_clear_action.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

void main() {
  test('bridge clear sends only explicit device confirmation', () async {
    final connection = _Connection();
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 2,
    );
    addTearDown(session.close);
    expect(await BridgeLocalEventClear(session).clear(), 'cleared');
    expect(connection.sent.single.accountContext, isNull);
    expect(connection.sent.single.payload, {
      'schemaVersion': 1,
      'confirmed': true,
    });
    expect(connection.sent.single.name, 'diagnostics.clearLocalEvents');
  });
  test('lost or malformed receipt never retries deletion', () async {
    final connection = _Connection()
      ..payload = {'schemaVersion': 1, 'outcome': 'cleared', 'extra': true};
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 2,
    );
    addTearDown(session.close);
    expect(await BridgeLocalEventClear(session).clear(), 'unknown');
    expect(connection.sent, hasLength(1));
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('confirm and cancel are explicit $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = _Port();
        var refreshes = 0;
        await tester.pumpWidget(
          _app(
            LocalEventClearAction(
              port: port,
              enabled: true,
              refresh: () async {
                refreshes++;
              },
            ),
            locale,
            mode,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('history-clear')));
        await tester.pumpAndSettle();
        expect(port.calls, 0);
        expect(find.byType(AlertDialog), findsOneWidget);
        Navigator.of(tester.element(find.byType(AlertDialog))).pop(false);
        await tester.pumpAndSettle();
        expect(port.calls, 0);
        expect(refreshes, 0);
        await tester.tap(find.byKey(const Key('history-clear')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('history-clear-confirm')));
        await tester.pumpAndSettle();
        expect(port.calls, 1);
        expect(refreshes, 1);
        expect(find.byKey(const Key('history-clear-result')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('close discards late outcome and cancels request', (
    tester,
  ) async {
    final port = _Port()..pending = Completer();
    var refreshes = 0;
    await tester.pumpWidget(
      _app(
        LocalEventClearAction(
          port: port,
          enabled: true,
          refresh: () async {
            refreshes++;
          },
        ),
        const Locale('en'),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear-confirm')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(port.cancelled, 1);
    port.pending!.completeError(StateError('late'));
    await tester.pump();
    expect(refreshes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed clear refreshes instead of inventing empty records', (
    tester,
  ) async {
    final port = _Port()..outcome = 'failed';
    var refreshes = 0;
    await tester.pumpWidget(
      _app(
        LocalEventClearAction(
          port: port,
          enabled: true,
          refresh: () async {
            refreshes++;
          },
        ),
        const Locale('en'),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not complete clearing. Try again.'),
      findsOneWidget,
    );
    expect(refreshes, 1);
    expect(port.calls, 1);
  });
}

Widget _app(Widget child, Locale locale, AppearanceMode mode) => MaterialApp(
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
  home: Scaffold(body: child),
);

class _Port implements LocalEventClearPort {
  int calls = 0, cancelled = 0;
  String outcome = 'cleared';
  Completer<String>? pending;
  @override
  Future<String> clear() async {
    calls++;
    return pending?.future ?? outcome;
  }

  @override
  void cancel() {
    cancelled++;
  }
}

class _Connection implements BridgeConnection {
  final controller = StreamController<BridgeEnvelope>();
  final sent = <BridgeEnvelope>[];
  Map<String, Object?> payload = {'schemaVersion': 1, 'outcome': 'cleared'};
  @override
  Stream<BridgeEnvelope> get incoming => controller.stream;
  @override
  Future<void> send(BridgeEnvelope request) async {
    sent.add(request);
    controller.add(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        status: 'ok',
        payload: payload,
      ),
    );
  }

  @override
  Future<void> close() => controller.close();
}
