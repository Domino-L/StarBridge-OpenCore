import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_loading.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_visible_receipts.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_startup_lifecycle.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

class StartupFixture {
  StartupFixture({this.payload = const {'schemaVersion': 1, 'safe': true}}) {
    session.acceptHostCapabilities(['applicationPreferences.menu.startup']);
    _subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      await gate?.future;
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          payload: payload,
          status: 'ok',
        ),
      );
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final session = BridgeClientSession(
    connection: pair.client,
    sessionGeneration: 7,
  );
  late final StreamSubscription<BridgeEnvelope> _subscription;
  Map<String, Object?> payload;
  Completer<void>? gate;
  final requests = <BridgeEnvelope>[];
  Future<void> close() async {
    await _subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}

void main() {
  testWidgets(
    'basic effects stay static without freezing switches or visible read receipts',
    (tester) async {
      final reads = <String>[];
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MenuPresentation(
              safeMode: true,
              child: StatefulBuilder(
                builder: (context, change) => Column(
                  children: [
                    const MenuLoading(),
                    Switch(
                      value: selected,
                      onChanged: (v) => change(() => selected = v),
                    ),
                    Expanded(
                      child: MenuVisibleReceipts(
                        active: true,
                        tokens: const {0: 'synthetic-receipt'},
                        onRead: reads.add,
                        builder: (keys) => ListView(
                          children: [
                            SizedBox(
                              key: keys[0],
                              height: 80,
                              child: const Text('Synthetic incoming message'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
      expect(reads, ['synthetic-receipt']);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(selected, true);
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
      expect(
        TickerMode.valuesOf(tester.element(find.byType(Switch))).enabled,
        true,
      );
      expect(reads, ['synthetic-receipt']);
      expect(tester.takeException(), isNull);
    },
  );
  for (final safe in [false, true]) {
    test('startup resolves once per UI runtime, safe=$safe', () async {
      final fixture = StartupFixture(
        payload: {'schemaVersion': 1, 'safe': safe},
      );
      addTearDown(fixture.close);
      final lifecycle = MenuStartupLifecycle();
      await lifecycle.prepare(fixture.session);
      expect(lifecycle.mode, safe ? 'safe' : 'normal');
      final request = fixture.requests.single;
      expect(request.name, 'applicationPreferences.menu.startup');
      expect(request.accountContext, isNull);
      expect(request.payload, {'schemaVersion': 1, 'token': lifecycle.token});
      expect(lifecycle.token, matches(RegExp(r'^[a-f0-9]{32}$')));
      fixture.payload = {'schemaVersion': 1, 'safe': !safe};
      await lifecycle.prepare(fixture.session);
      final replacement = StartupFixture();
      addTearDown(replacement.close);
      await lifecycle.prepare(replacement.session);
      expect(fixture.requests, hasLength(1));
      expect(replacement.requests, isEmpty);
      expect(lifecycle.mode, safe ? 'safe' : 'normal');
    });
  }
  for (final bad in [
    {'schemaVersion': 1, 'safe': 'true'},
    {'schemaVersion': 2, 'safe': true},
    {'schemaVersion': 1, 'safe': true, 'account': 'forbidden'},
    {'schemaVersion': 1},
  ]) {
    test('unknown startup result is not consumption: $bad', () async {
      final fixture = StartupFixture(payload: bad);
      addTearDown(fixture.close);
      final lifecycle = MenuStartupLifecycle();
      await lifecycle.prepare(fixture.session);
      expect(lifecycle.mode, 'unverified');
      expect(lifecycle.protectsLayout, true);
      fixture.payload = {'schemaVersion': 1, 'safe': true};
      await lifecycle.prepare(fixture.session);
      expect(lifecycle.mode, 'safe');
      expect(fixture.requests, hasLength(2));
      expect(fixture.requests.first.payload, fixture.requests.last.payload);
    });
  }
  test('concurrent composition attempts share one startup request', () async {
    final fixture = StartupFixture()..gate = Completer<void>();
    addTearDown(fixture.close);
    final lifecycle = MenuStartupLifecycle();
    final first = lifecycle.prepare(fixture.session);
    final second = lifecycle.prepare(fixture.session);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.requests, hasLength(1));
    expect(lifecycle.mode, 'unverified');
    fixture.gate!.complete();
    await Future.wait([first, second]);
    expect(lifecycle.mode, 'safe');
  });
  test('safe presentation and changes protect normal layout without swallowing explicit settings', () async {
    final fixture = StartupFixture();
    addTearDown(fixture.close);
    final lifecycle = MenuStartupLifecycle();
    await lifecycle.prepare(fixture.session);
    final current = MenuWindowPreferences(
      8,
      const {
        'version': 1,
        'panels': [
          {
            'id': 'browser',
            'bounds': [20, 40, 500, 350],
          },
        ],
        'open': ['friends', 'browser'],
      },
      {...MenuWindowPreferences.defaults.settings, 'restoreDesktop': true},
    );
    final presented = lifecycle.presentation(current);
    expect(presented.layout['open'], isEmpty);
    final proposed = MenuWindowPreferences(
      8,
      const {'version': 1, 'panels': [], 'open': []},
      {...current.settings, 'safeModeNextLaunch': true, 'snapWindows': true},
    );
    final changes = lifecycle.changes(current, proposed);
    expect(changes.layout, current.layout);
    expect(changes.settings['safeModeNextLaunch'], true);
    expect(changes.settings['snapWindows'], true);
    expect(changes.revision, 8);
    expect(current.layout['open'], ['friends', 'browser']);
    final disabled = lifecycle.changes(
      current,
      proposed.withSettingsPatch({
        'restoreDesktop': false,
        'restoreAfterRestart': false,
      }),
    );
    expect(disabled.layout['open'], isEmpty);
    expect(disabled.layout['panels'], current.layout['panels']);
  });
}
