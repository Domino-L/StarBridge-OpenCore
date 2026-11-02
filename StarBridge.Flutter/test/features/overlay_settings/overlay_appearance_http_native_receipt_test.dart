import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_collection_panel.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_progress.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../friends/social_layout_test.dart' show app, size;

// Replays completed synthetic loopback HTTP -> actual Account Host -> Native
// Bridge receipts through the production Flutter adapter and collection panel.
// No commercial threshold implementation or account/credential fixture lives
// in this repository. Missing external evidence is explicitly skipped.
void main() {
  final reportPath = Platform.environment['STARBRIDGE_HTTP_NATIVE_REPORT'];
  for (final label in [
    'actual-http-account-native-bridge-confirmed',
    'actual-host-epoch-native-bridge-readonly-replacement',
  ]) {
    testWidgets(
      'completed actual HTTP Native receipt renders readonly: $label',
      (tester) async {
        final report = jsonDecode(File(reportPath!).readAsStringSync()) as Map;
        expect(report['passed'], isTrue);
        expect(report['finished'], isTrue);
        expect(report['actualHttp'], isTrue);
        expect(report['actualCloud'], isFalse);
        expect(report['normalEligibilityGrant'], isFalse);
        expect(report['httpMethods'], ['GET', 'GET']);
        final row = (report['stages'] as List).singleWhere(
          (value) => value['label'] == label,
        );
        final source = Map<String, Object?>.from(row['collection'] as Map);
        final id = source['appearanceId'] as String;
        final receipt = OverlayAppearanceProgress.fromMap(
          source,
          appearanceId: id,
        );
        expect(receipt.state, 'ready');
        expect(receipt.items.length, 7);
        expect(receipt.items.where((item) => item.owned).length, 1);
        if (label == 'actual-http-account-native-bridge-confirmed') {
          expect(receipt.confirmedUsageMs, greaterThan(0));
        } else {
          expect(receipt.confirmedUsageMs, 0);
        }
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
        )..acceptHostCapabilities(['overlay.appearanceProgress']);
        final requests = <BridgeEnvelope>[];
        final subscription = pair.host.incoming.listen((request) {
          if (request.messageType != 'request') return;
          requests.add(request);
          unawaited(
            pair.host.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'response',
                name: request.name,
                correlationId: request.correlationId,
                sessionGeneration: request.sessionGeneration,
                status: 'ok',
                payload: source,
              ),
            ),
          );
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
        expect(tester.takeException(), isNull);
        expect(find.text('初始拥有'), findsOneWidget);
        expect(find.text('已解锁'), findsNothing);
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('appearance-collection-usage')),
              )
              .data,
          startsWith('已确认使用：'),
        );
        for (final item in receipt.items) {
          final text = tester
              .widget<Text>(
                find.byKey(Key('appearance-collection-item-${item.id}')),
              )
              .data;
          expect(text, item.owned ? '初始拥有' : startsWith('还需使用 '));
          if (!item.owned) {
            expect(
              item.remainingMs,
              item.requiredUsageMs - receipt.confirmedUsageMs!,
            );
          }
        }
        expect(requests, hasLength(1));
        expect(requests.single.name, 'overlay.appearanceProgress.read');
        expect(requests.single.payload, {
          'schemaVersion': 1,
          'appearanceId': id,
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      skip: reportPath == null,
    );
  }
}
