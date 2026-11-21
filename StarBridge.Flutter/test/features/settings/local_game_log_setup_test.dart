import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/game_log/local_game_log_setup_panel.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../onboarding/bridge_onboarding_adapter_test.dart' show wire;

void main() {
  for (final allowOnlineSetup in [false, true]) {
    testWidgets('unfinished setup retries in panel (online=$allowOnlineSetup)', (
      tester,
    ) async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      session.acceptHostCapabilities(['onboarding.firstUse.v1']);
      final payload = wire();
      final facts = payload['facts']! as Map<String, Object?>;
      facts.addAll({
        'localIdentityConfirmed': true,
        'logSetupPending': true,
        'onlineSetupPending': allowOnlineSetup,
      });
      final actions = <String>[];
      final subscription = pair.host.incoming.listen((request) {
        if (request.messageType != 'request') return;
        if (request.name == 'onboarding.execute') {
          final action = request.payload['action']! as String;
          actions.add(action);
          if (action == 'finishLogSetup') facts['logSetupPending'] = false;
        }
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 7,
              status: 'ok',
              payload: payload,
            ),
          ),
        );
      });
      var confirmed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('en', 'US'),
          ),
          home: Scaffold(
            body: LocalGameLogSetupPanel(
              session: session,
              allowOnlineSetup: allowOnlineSetup,
              onConfirmed: () async {
                confirmed++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      const explanation =
          "Your game log is confirmed, but the statistics setting hasn't been saved yet.";
      expect(find.text(explanation), findsOneWidget);
      expect(
        find.byKey(const Key('local-settings-confirm-handle')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('local-settings-refresh-log')));
      await tester.pumpAndSettle();
      expect(actions, ['locateLogs', 'locateLogs']);
      expect(find.text(explanation), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('local-settings-finish-log-setup')),
      );
      await tester.pumpAndSettle();
      expect(actions, ['locateLogs', 'locateLogs', 'finishLogSetup']);
      expect(find.text(explanation), findsNothing);
      expect(confirmed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      });
    });
  }
  testWidgets(
    'completed local setup without an account can select a log and confirm Host identity in settings',
    (tester) async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 7,
      );
      session.acceptHostCapabilities(['onboarding.firstUse.v1']);
      final actions = <String>[];
      var payload = wire();
      (payload['facts']! as Map<String, Object?>).addAll({
        'eligibility': 'returning',
        'sourceKey': null,
        'evidenceKey': null,
        'version': null,
        'logReady': false,
        'logDeferred': true,
        'evidence': 'unavailable',
        'origin': null,
        'handle': null,
        'observedAt': null,
      });
      payload['completed'] = <String, Object?>{
        'step': 'summary',
        'mode': 'local',
        'sourceKey': null,
        'evidenceKey': null,
      };
      final subscription = pair.host.incoming.listen((request) {
        if (request.messageType != 'request') return;
        if (request.accountContext != null) {
          throw StateError('Local settings sent an account context');
        }
        if (request.name == 'onboarding.execute') {
          final action = request.payload['action']! as String;
          actions.add(action);
          if (action == 'selectLog') payload = wire();
          if (action == 'confirmHandle') {
            (payload['facts']!
                    as Map<String, Object?>)['localIdentityConfirmed'] =
                true;
          }
        } else {
          if (request.name != 'onboarding.read') {
            throw StateError('Unexpected settings request');
          }
        }
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 7,
              status: 'ok',
              payload: payload,
            ),
          ),
        );
      });
      var confirmed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('en', 'US'),
          ),
          home: Scaffold(
            body: LocalGameLogSetupPanel(
              session: session,
              onConfirmed: () async {
                confirmed++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('local-settings-select-log')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('local-settings-select-log')));
      await tester.pumpAndSettle();
      expect(find.text('Pilot-Example'), findsOneWidget);
      await tester.tap(find.byKey(const Key('local-settings-confirm-handle')));
      await tester.pumpAndSettle();
      expect(actions, ['locateLogs', 'selectLog', 'refresh', 'confirmHandle']);
      expect(confirmed, 1);
      expect(
        find.byKey(const Key('local-settings-confirm-handle')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      });
    },
  );
}
