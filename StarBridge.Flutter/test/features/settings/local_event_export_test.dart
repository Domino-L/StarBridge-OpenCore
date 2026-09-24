import 'dart:async';

import 'package:flutter/material.dart' hide LocalHistoryEntry;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/local_event_export.dart';
import 'package:starbridge_flutter/features/settings/local_event_export_action.dart';
import 'package:starbridge_flutter/features/settings/local_event_history.dart';
import 'package:starbridge_flutter/features/settings/local_event_history_dialog.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

void main() {
  for (final available in [false, true]) {
    testWidgets('ordinary history opener gates export capability: $available', (
      tester,
    ) async {
      final connection = _Connection();
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 2,
      );
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showLocalEventHistory(
                context,
                session: session,
                available: true,
                exportAvailable: available,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('history-export')),
      );
      expect(button.onPressed != null, available);
      if (available) {
        await tester.tap(find.byKey(const Key('history-export')));
        await tester.pumpAndSettle();
        expect(find.text('已导出 125 条记录'), findsOneWidget);
      }
      expect(
        connection.sent.where((e) => e.name == 'diagnostics.exportLocalEvents'),
        hasLength(available ? 1 : 0),
      );
      await tester.tap(find.byKey(const Key('history-close')));
      await tester.pumpAndSettle();
    });
  }
  test(
    'bridge sends device request without selected category, rows or path',
    () async {
      final connection = _Connection();
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 2,
      );
      addTearDown(session.close);
      final result = await BridgeLocalEventExport(session).export('zh-CN');
      expect(result.code, 'saved');
      expect(result.count, 125);
      expect(connection.sent.single.name, 'diagnostics.exportLocalEvents');
      expect(connection.sent.single.accountContext, isNull);
      expect(connection.sent.single.payload, {
        'schemaVersion': 1,
        'locale': 'zh-CN',
      });
    },
  );
  for (final invalid in [
    {'schemaVersion': 1, 'outcome': 'saved', 'count': 0, 'recovered': false},
    {'schemaVersion': 1, 'outcome': 'saved', 'count': 3001, 'recovered': false},
    {'schemaVersion': 1, 'outcome': 'saved', 'count': 2, 'recovered': 'false'},
    {
      'schemaVersion': 1,
      'outcome': 'cancelled',
      'count': 2,
      'recovered': false,
    },
    {
      'schemaVersion': 1,
      'outcome': 'saved',
      'count': 2,
      'recovered': false,
      'path': 'unexpected',
    },
  ]) {
    test('invalid export receipt remains unconfirmed: $invalid', () async {
      final connection = _Connection()..payload = invalid;
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 2,
      );
      addTearDown(session.close);
      expect(
        (await BridgeLocalEventExport(session).export('en')).code,
        'unknown',
      );
      expect(connection.sent, hasLength(1));
    });
  }
  for (final pair in {
    'file_exists': 'fileExists',
    'invalid_destination': 'invalidDestination',
    'data_unavailable': 'dataUnavailable',
    'empty': 'empty',
    'unavailable': 'unavailable',
    'busy': 'busy',
    'save_failed': 'failed',
  }.entries) {
    test('bridge maps ${pair.key} without exposing raw error', () async {
      final connection = _Connection()..error = 'localEventsExport.${pair.key}';
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 2,
      );
      addTearDown(session.close);
      expect(
        (await BridgeLocalEventExport(session).export('en')).code,
        pair.value,
      );
    });
  }
  test('pending bridge operation coalesces and cancels', () async {
    final connection = _Connection()..hold = true;
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 2,
    );
    addTearDown(session.close);
    final port = BridgeLocalEventExport(session);
    final pending = port.export('en');
    expect((await port.export('en')).code, 'busy');
    port.cancel();
    await pending;
    expect(
      connection.sent.where((e) => e.name == 'diagnostics.exportLocalEvents'),
      hasLength(1),
    );
    expect(connection.sent.any((e) => e.name == 'bridge.cancel'), isTrue);
  });

  testWidgets('actual history dialog exports even when filter has no rows', (
    tester,
  ) async {
    final controller = LocalHistoryController(_History());
    final export = _Export();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => LocalEventHistoryDialog(
                controller: controller,
                exportPort: export,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await controller.select('life');
    await tester.pumpAndSettle();
    expect(controller.value.page!.entries, isEmpty);
    expect(controller.value.page!.totalCount, 125);
    await tester.tap(find.byKey(const Key('history-export')));
    await tester.pumpAndSettle();
    expect(export.calls, 1);
    expect(find.text('已导出 125 条记录'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('history-clear')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('history-close')));
    await tester.pumpAndSettle();
    expect(export.cancels, greaterThan(0));
  });
  testWidgets('close pending export cancels and ignores late failure', (
    tester,
  ) async {
    final export = _Export()..pending = Completer();
    await tester.pumpWidget(
      _app(LocalEventExportAction(port: export, enabled: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-export')));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('history-export')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    expect(export.cancels, 1);
    export.pending!.completeError(StateError('late'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('unreadable or absent history cannot export', (tester) async {
    final export = _Export();
    await tester.pumpWidget(
      _app(LocalEventExportAction(port: export, enabled: false)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('history-export')))
          .onPressed,
      isNull,
    );
    expect(export.calls, 0);
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('narrow export error stays readable $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final export = _Export()
          ..result = const LocalEventExportResult('unknown');
        final controller = LocalHistoryController(_History());
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            LocalEventHistoryDialog(controller: controller, exportPort: export),
            locale: locale,
            mode: mode,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('history-export')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history-export-result')), findsOneWidget);
        expect(export.calls, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Widget _app(
  Widget body, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
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
  home: Scaffold(body: body),
);

class _Export implements LocalEventExportPort {
  int calls = 0, cancels = 0;
  Completer<LocalEventExportResult>? pending;
  LocalEventExportResult result = const LocalEventExportResult(
    'saved',
    count: 125,
  );
  @override
  Future<LocalEventExportResult> export(String locale) async {
    calls++;
    return pending?.future ?? result;
  }

  @override
  void cancel() {
    cancels++;
  }
}

class _History implements LocalHistoryPort {
  @override
  Future<LocalHistoryPage> read({
    required String category,
    required int offset,
    required int pageSize,
    String? revision,
  }) async => LocalHistoryPage(
    state: 'ready',
    totalCount: 125,
    filteredCount: 0,
    offset: 0,
    pageSize: 50,
    hasMore: false,
    entries: const [],
    revision: 'A' * 64,
  );
}

class _Connection implements BridgeConnection {
  final incomingController = StreamController<BridgeEnvelope>();
  final sent = <BridgeEnvelope>[];
  bool hold = false;
  String? error;
  Map<String, Object?> payload = {
    'schemaVersion': 1,
    'outcome': 'saved',
    'count': 125,
    'recovered': false,
  };
  @override
  Stream<BridgeEnvelope> get incoming => incomingController.stream;
  @override
  Future<void> send(BridgeEnvelope request) async {
    sent.add(request);
    if (hold) return;
    incomingController.add(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        status: error == null ? 'ok' : 'error',
        payload: request.name == 'diagnostics.getLocalEvents'
            ? {
                'schemaVersion': 1,
                'state': 'ready',
                'totalCount': 1,
                'filteredCount': 1,
                'offset': 0,
                'pageSize': 50,
                'hasMore': false,
                'revision': 'A' * 64,
                'entries': [
                  {
                    'id': 'test',
                    'occurredAt': '2026-09-10T12:00:00+00:00',
                    'category': 'ship',
                    'eventType': 'Synthetic',
                    'title': 'Title',
                    'detail': 'Detail',
                  },
                ],
              }
            : payload,
        error: error == null
            ? null
            : BridgeErrorBody(
                code: error!,
                message: 'internal error',
                retryable: true,
              ),
      ),
    );
  }

  @override
  Future<void> close() => incomingController.close();
}
