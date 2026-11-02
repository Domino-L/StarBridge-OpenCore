import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_collection_panel.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../friends/social_layout_test.dart' show app, size;

// Replays completed, external synthetic HTTP/Host/Native evidence through the
// production Flutter session/adapter/panel. No credentials, private thresholds
// or receipt fixtures are stored here. This is not a live product-pipe test.
void main() {
  final reportPath =
      Platform.environment['STARBRIDGE_HTTP_NATIVE_LATENCY_REPORT'];
  for (final changedOwner in [false, true]) {
    testWidgets(
      'actual Native delayed-read cancellation and recovery, owner change: $changedOwner',
      (tester) async {
        final report = jsonDecode(File(reportPath!).readAsStringSync()) as Map;
        expect(report['passed'], isTrue);
        expect(report['finished'], isTrue);
        expect(report['actualHttp'], isTrue);
        expect(report['actualCloud'], isFalse);
        expect(report['normalEligibilityGrant'], isFalse);
        expect(report['physicalSuspend'], isFalse);
        expect(report['latency'], isTrue);
        expect(report['httpMethods'], ['GET', 'GET', 'GET']);
        Map stage(String label) => (report['stages'] as List).singleWhere(
          (value) => value['label'] == label,
        ) as Map;
        final initial = Map<String, Object?>.from(
          stage('actual-http-account-native-bridge-confirmed')['collection']
              as Map,
        );
        final replacement = Map<String, Object?>.from(
          stage(
                'actual-host-epoch-native-bridge-readonly-replacement',
              )['collection']
              as Map,
        );
        final cancelled =
            stage(
                  'real-http-former-account-late-read-six-second-bridge-timeout',
                )['reply']
                as Map;
        expect(cancelled['Status'], 'cancelled');
        expect(cancelled['Payload'], isEmpty);
        final error = cancelled['Error'] as Map;
        expect(error['Code'], 'bridge.cancelled');
        expect(initial['confirmedUsageMs'], greaterThan(0));
        expect(replacement['confirmedUsageMs'], 0);
        final id = initial['appearanceId'] as String;
        expect(replacement['appearanceId'], id);
        final reaction = stage(
          'ordinary-preview-source-companion-response-during-authenticated-read-wait',
        );
        expect(reaction['manualPetAction'], isFalse);
        expect(reaction['pet']['responses'], greaterThan(0));

        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
        )..acceptHostCapabilities(['overlay.appearanceProgress']);
        final requests = <BridgeEnvelope>[];
        Future<void> ready(BridgeEnvelope request, Map<String, Object?> body) =>
            pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'response',
                name: request.name,
                correlationId: request.correlationId,
                sessionGeneration: request.sessionGeneration,
                status: 'ok',
                payload: body,
              ),
            );
        final subscription = pair.host.incoming.listen((request) {
          if (request.messageType != 'request') return;
          requests.add(request);
          if (requests.length == 1) unawaited(ready(request, initial));
        });
        addTearDown(() async {
          await subscription.cancel();
          await session.close();
          await pair.host.close();
        });
        size(tester, const Size(420, 900));
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: OverlayAppearanceCollectionPanel(
                appearanceId: id,
                port: BridgeOverlayWorkspaceAdapter(session),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('已同步'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('appearance-collection-refresh')),
        );
        await tester.pump();
        expect(requests, hasLength(2));
        final former = requests.last;
        if (changedOwner) {
          await pair.host.send(
            const BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'event',
              name: 'account.changed',
              sessionGeneration: 2,
              sequence: 1,
              payload: {'schemaVersion': 1},
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(requests, hasLength(3));
          expect(requests.last.sessionGeneration, 2);
          expect(find.text('使用进度尚未同步'), findsOneWidget);
        }
        // Only correlations/generation are adapted to this in-memory replay;
        // cancelled status, empty body and error are from the actual Native run.
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: former.name,
            correlationId: former.correlationId,
            sessionGeneration: former.sessionGeneration,
            status: cancelled['Status'] as String,
            payload: Map<String, Object?>.from(cancelled['Payload'] as Map),
            error: BridgeErrorBody(
              code: error['Code'] as String,
              message: error['Message'] as String,
              retryable: error['Retryable'] as bool,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('使用进度尚未同步'), findsOneWidget);
        expect(find.text('已同步'), findsNothing);
        if (changedOwner) {
          expect(find.text('未能读取收藏，请刷新重试。'), findsNothing);
          expect(find.text('正在读取账号收藏…'), findsOneWidget);
        } else {
          expect(find.text('未能读取收藏，请刷新重试。'), findsOneWidget);
          await tester.tap(
            find.byKey(const Key('appearance-collection-refresh')),
          );
          await tester.pump();
          expect(requests, hasLength(3));
        }
        await ready(requests.last, replacement);
        await tester.pumpAndSettle();
        expect(find.text('已同步'), findsOneWidget);
        expect(find.text('使用进度尚未同步'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(
          requests.every((r) => r.name == 'overlay.appearanceProgress.read'),
          isTrue,
        );
        expect(
          requests.every(
            (r) =>
                r.payload.length == 2 &&
                r.payload['schemaVersion'] == 1 &&
                r.payload['appearanceId'] == id,
          ),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      skip: reportPath == null,
    );
  }
}
