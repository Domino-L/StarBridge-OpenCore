import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_section.dart';

import '../communities/community_workspace_test.dart' show WorkspaceTestPort;
import '../communities/community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

class _Port implements OfficialFleetShipsPort {
  _Port(this.asset);
  final String? asset;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  Future<OfficialFleetShipsSnapshot> read(
    OfficialFleetShipsQuery query,
  ) async => OfficialFleetShipsSnapshot.available(
    query: query,
    ships: [
      OfficialFleetSharedShip(
        shipRef: 'test-ship',
        displayName: 'Test Ship',
        modelCode: 'test',
        ownerDisplay: 'Pilot',
        ownerCallsign: 'Pilot',
        size: OfficialFleetShipSize.small,
        roleLabel: 'Utility',
        catalogStatus: OfficialFleetShipCatalogStatus.flightReady,
        requestState: OfficialFleetShipRequestState.requestable,
        priceUsd: 100,
        imageUrl: 'https://example.invalid/legacy-custom.png',
        catalogImageAsset: asset,
      ),
    ],
    totalCount: 1,
    requestableCount: 1,
    ownerCount: 1,
    totalValueUsd: 100,
    totalPages: 1,
    sizeCounts: const {OfficialFleetShipSize.small: 1},
  );
}

void main() {
  setUpAll(loadFonts);
  for (final asset in [
    null,
    'https://example.invalid/custom.png',
    'assets/ships/../custom.png',
    'assets/ships/catalog-test.png',
  ]) {
    testWidgets('official fleet uses catalog only: $asset', (tester) async {
      tester.view.physicalSize = const Size(1200, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = createOfficialFleetShipsModule(_Port(asset));
      addTearDown(module.dispose);
      final workspace = WorkspaceTestPort();
      addTearDown(workspace.changes.close);
      final app = host(workspace, const Locale('en')) as MaterialApp;
      await tester.pumpWidget(
        MaterialApp(
          theme: app.theme,
          locale: app.locale,
          supportedLocales: app.supportedLocales,
          localizationsDelegates: app.localizationsDelegates,
          home: Scaffold(
            body: OfficialFleetShipsSection(sourceRef: 'fleet', module: module),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images.where((w) => w.image is NetworkImage), isEmpty);
      if (asset == 'assets/ships/catalog-test.png') {
        // A missing packaged asset has a visible placeholder, never URL fallback.
        expect(images.single.image, isA<AssetImage>());
        expect((images.single.image as AssetImage).assetName, asset);
      } else {
        expect(images, isEmpty);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
