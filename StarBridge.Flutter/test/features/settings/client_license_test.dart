import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/client_license.dart';
import 'package:starbridge_flutter/features/settings/client_license_dialog.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

const _terms = 'SYNTHETIC FULL LICENSE\r\n\r\n1. Full body 原文\r\nEnd of terms';

void main() {
  test('missing capability sends no request', () async {
    final connection = _Connection();
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 4,
    );
    addTearDown(session.close);
    expect(
      (await BridgeClientLicense(session, available: false).read()).state,
      ClientLicenseState.unavailable,
    );
    expect(connection.sent, isEmpty);
  });
  test('read is accountless, exact and preserves full text', () async {
    final connection = _Connection();
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 4,
    );
    addTearDown(session.close);
    final result = await BridgeClientLicense(session, available: true).read();
    expect(result.text, _terms);
    final request = connection.sent.single;
    expect(request.name, 'legal.getClientLicense');
    expect(request.accountContext, isNull);
    expect(request.payload, {'schemaVersion': 1});
  });
  for (final state in ['missing', 'unreadable']) {
    test('preserves $state without fake body', () async {
      final connection = _Connection()
        ..payload = {'schemaVersion': 1, 'state': state, 'text': null};
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 4,
      );
      addTearDown(session.close);
      final result = await BridgeClientLicense(session, available: true).read();
      expect(result.state.name, state);
      expect(result.text, isNull);
    });
  }
  final invalids = <String, Map<String, Object?>>{
    'schema': {'schemaVersion': 2, 'state': 'ready', 'text': _terms},
    'missing field': {'schemaVersion': 1, 'state': 'missing'},
    'extra path': {
      'schemaVersion': 1,
      'state': 'ready',
      'text': _terms,
      'path': 'private',
    },
    'empty': {'schemaVersion': 1, 'state': 'ready', 'text': '  '},
    'oversized': {'schemaVersion': 1, 'state': 'ready', 'text': 'x' * 65537},
    'control': {
      'schemaVersion': 1,
      'state': 'ready',
      'text': 'body\u0000private',
    },
    'wrong state': {'schemaVersion': 1, 'state': 'accepted', 'text': _terms},
    'error with body': {'schemaVersion': 1, 'state': 'missing', 'text': _terms},
  };
  for (final item in invalids.entries) {
    test('rejects ${item.key}', () async {
      final connection = _Connection()..payload = item.value;
      final session = BridgeClientSession(
        connection: connection,
        sessionGeneration: 4,
      );
      addTearDown(session.close);
      await expectLater(
        BridgeClientLicense(session, available: true).read(),
        throwsFormatException,
      );
    });
  }
  testWidgets('button is lazy and opens a single full read-only document', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      _app(() async {
        reads++;
        return const ClientLicenseDocument(ClientLicenseState.ready, _terms);
      }),
    );
    expect(reads, 0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('client-license-open')));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('client-license-body')))
          .data,
      _terms,
    );
    expect(find.text('同意'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.byKey(const Key('client-license-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-license-dialog')), findsNothing);
  });
  testWidgets('repeated activation before rebuild opens only once', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      _app(() async {
        reads++;
        return const ClientLicenseDocument(ClientLicenseState.ready, _terms);
      }),
    );
    await tester.pumpAndSettle();
    final activate = tester
        .widget<OutlinedButton>(find.byKey(const Key('client-license-open')))
        .onPressed!;
    activate();
    activate();
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byKey(const Key('client-license-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('client-license-close')));
    await tester.pumpAndSettle();
  });
  testWidgets('late response after close cannot reopen document', (
    tester,
  ) async {
    final pending = Completer<ClientLicenseDocument>();
    await tester.pumpWidget(_app(() => pending.future));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('client-license-open')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('client-license-close')));
    await tester.pumpAndSettle();
    pending.complete(
      const ClientLicenseDocument(ClientLicenseState.ready, _terms),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-license-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('errors hide raw details and retry reads again', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      _app(() async {
        if (reads++ == 0) throw StateError('private path and token');
        return const ClientLicenseDocument(ClientLicenseState.ready, _terms);
      }),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('client-license-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.byKey(const Key('client-license-retry')));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.byKey(const Key('client-license-body')), findsOneWidget);
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('narrow scrollable document and errors $locale $mode', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var failed = true;
        await tester.pumpWidget(
          _app(
            () async => failed
                ? const ClientLicenseDocument(ClientLicenseState.missing)
                : ClientLicenseDocument(
                    ClientLicenseState.ready,
                    List.filled(100, _terms).join('\n'),
                  ),
            locale: locale,
            mode: mode,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('client-license-open')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('client-license-error')), findsOneWidget);
        failed = false;
        await tester.tap(find.byKey(const Key('client-license-retry')));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('client-license-close')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Widget _app(
  ClientLicenseRead read, {
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
  home: Scaffold(
    body: ClientLicenseButton(
      open: (context) => showClientLicenseDialog(context, read: read),
    ),
  ),
);

class _Connection implements BridgeConnection {
  final _incoming = StreamController<BridgeEnvelope>();
  final sent = <BridgeEnvelope>[];
  Map<String, Object?> payload = {
    'schemaVersion': 1,
    'state': 'ready',
    'text': _terms,
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
        payload: payload,
      ),
    );
  }

  @override
  Future<void> close() async => _incoming.close();
}
