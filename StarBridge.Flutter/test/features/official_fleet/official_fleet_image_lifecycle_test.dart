import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_shared_ships.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'official_fleet_image_test_support.dart';
import 'official_fleet_hangar_sharing_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final cause in ['account', 'generation', 'host']) {
    testWidgets(
      'actual Bridge $cause retirement closes dispatched report route',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final wire = ImageWire(
          capabilities: ['officialFleet.ships', ...imageNames],
        );
        final adapter = BridgeOfficialFleetSharedShips(
          wire.session,
          sourceRef: () => wire.sourceChanges.value,
          sourceChanges: wire.sourceChanges,
        );
        addTearDown(() async {
          await adapter.close();
          await wire.close();
        });
        wire.respond = (r) => switch (r.name) {
          'officialFleet.ships' => imagePage(r.payload),
          'officialFleet.shipImage' => imageChunk(r.payload),
          'officialFleet.reportShipImage' => {
            ...r.payload,
            'status': 'unknown',
            'error': 'outcomeUnknown',
          },
          _ => throw StateError('Unexpected request ${r.name}'),
        };
        final decoded = (await tester.runAsync(
          () => decodeCommunityImage(pngBytes, 1024),
        ))!;
        addTearDown(decoded.dispose);
        final page = CommunityShipsPage.parse(
          imagePage({
            'sourceRef': source,
            'targetRef': ref(9),
            'offset': 0,
            'query': CommunityShipQuery().toPayload(),
          }),
          officialImages: true,
        );
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showStarBridgeDialog<void>(
                  context,
                  builder: (_) => CommunityShipDetailDialog(
                    port: adapter,
                    page: page,
                    shipRef: ref(1),
                    ownerTargetFactory: null,
                    imageDecoder: (_, _) async => decoded.clone(),
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
        await tester.tap(find.byKey(const Key('community-ship-report-image')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ship-report-reason-control')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Inappropriate content').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('ship-report-details')),
          'Reporter-owned draft',
        );
        await tester.tap(find.byKey(const Key('ship-report-submit')));
        await tester.pumpAndSettle();
        expect(find.text('Check result'), findsOneWidget);
        expect(
          wire.requests
              .where((r) => r.name == 'officialFleet.reportShipImage')
              .length,
          1,
        );
        switch (cause) {
          case 'account':
            await wire.wire.send(
              BridgeEnvelope(
                protocolVersion: 1,
                messageType: 'event',
                name: 'account.changed',
                sessionGeneration: 2,
                sequence: 1,
                payload: const {},
              ),
            );
          case 'generation':
            wire.session.advanceGeneration(2);
          case 'host':
            // Actual transport done is the Host loss boundary. Closing the
            // peer's inbound test stream would not disconnect this client.
            await wire.client.close();
        }
        await tester.pumpAndSettle();
        expect(find.byType(CommunityShipReportDialog), findsNothing);
        expect(find.byType(CommunityShipDetailDialog), findsNothing);
        expect(find.text('Reporter-owned draft'), findsNothing);
        expect(
          wire.requests.where(
            (r) => r.name == 'officialFleet.shipImageReportStatus',
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
