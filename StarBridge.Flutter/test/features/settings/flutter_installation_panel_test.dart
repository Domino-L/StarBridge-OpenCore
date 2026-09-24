import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/flutter_installation_panel.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'settings_entry_test.dart' show app;

void main() {
  testWidgets('scan is explicit and cancellation does not uninstall', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.close);
    await tester.pumpWidget(
      app(
        FlutterInstallationPanel(session: harness.session),
        const Locale('zh', 'CN'),
        GlobalKey(),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.requests, isEmpty);
    await tester.tap(find.byKey(const Key('flutter-installation-scan')));
    await tester.pumpAndSettle();
    expect(harness.requests.single.payload, {'schemaVersion': 1});
    await tester.tap(find.byKey(const Key('flutter-installation-uninstall')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();
    expect(harness.requests.length, 1);
    await tester.tap(find.byKey(const Key('flutter-installation-uninstall')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      harness.requests.last.name,
      'diagnostics.flutterInstallationExecute',
    );
    expect(harness.requests.last.payload, {
      'schemaVersion': 1,
      'ticket': 'fixture-ticket',
      'action': 'uninstall',
    });
    expect(harness.requests.last.accountContext, isNull);
    expect(
      find.byKey(const Key('flutter-installation-uninstall')),
      findsNothing,
    );
    expect(find.text('卸载向导已启动，请在向导中继续。'), findsOneWidget);
  });

  testWidgets('portable scan hides irrelevant actions at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _Harness(portable: true);
    addTearDown(harness.close);
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: FlutterInstallationPanel(session: harness.session),
        ),
        const Locale('en', 'US'),
        GlobalKey(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flutter-installation-scan')));
    await tester.pumpAndSettle();
    for (final key in ['uninstall', 'clean']) {
      expect(find.byKey(Key('flutter-installation-$key')), findsNothing);
    }
    expect(tester.takeException(), isNull);
    expect(
      find.text('No installation remnants need cleaning.'),
      findsOneWidget,
    );
    expect(find.textContaining('Flutter'), findsNothing);
    expect(find.textContaining('WPF'), findsNothing);
    expect(harness.requests.length, 1);
  });
}

class _Harness {
  _Harness({bool portable = false}) {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 1)
      ..acceptHostCapabilities(['diagnostics.flutterInstallation']);
    subscription = host.incoming.listen((request) async {
      requests.add(request);
      await host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: 1,
          status: 'ok',
          payload: request.name.endsWith('Execute')
              ? {'schemaVersion': 1, 'completed': true}
              : {
                  'schemaVersion': 1,
                  'ticket': 'fixture-ticket',
                  'mode': portable ? 'portable' : 'installed',
                  'directory': portable ? '' : r'C:\Example\Flutter',
                  'canUninstall': !portable,
                  'canClean': false,
                },
        ),
      );
    });
  }
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}
