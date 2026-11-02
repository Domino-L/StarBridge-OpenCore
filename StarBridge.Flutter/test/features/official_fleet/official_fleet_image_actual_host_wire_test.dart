import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_ship_image_port.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_hangar_sharing.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_shared_ships.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'official_fleet_image_test_support.dart';

// Exact payload bytes exported by actual package-C Dispatcher→Host→local HTTP.
// The two scenes use distinct synthetic accounts. They are offline wire replay,
// not a real account/service run. Provenance and all file hashes sit beside them.
Map<String, Object?> _read(String name) => (jsonDecode(
  File('test/fixtures/official_fleet/custom_images/$name').readAsStringSync(),
) as Map).cast<String, Object?>();

void main() {
  for (final anonymous in [false, true]) {
    test(
      'actual C ${anonymous ? 'restricted' : 'visible'} public image bytes reach common assembly',
      () async {
        final page = _read(
          anonymous ? 'bridge-anonymous-page.json' : 'bridge-public-page.json',
        );
        final pageRequest = _read('request-officialFleet-ships.json');
        final imageRequest = _read('request-officialFleet-shipImage.json');
        final wire = ImageWire(
          capabilities: ['officialFleet.ships', ...imageNames],
          account: const BridgeAccountContext(
            environment: 'synthetic',
            authority: 'scm',
            subject: 'public-viewer-scene',
          ),
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
        wire.respond = (request) {
          switch (request.name) {
            case 'officialFleet.ships':
              expect(request.payload, pageRequest);
              return page;
            case 'officialFleet.shipImage':
              expect(request.payload, imageRequest);
              return _read('bridge-image-chunk.json');
            default:
              throw StateError('Unexpected replay command ${request.name}');
          }
        };
        final parsed = await adapter.readShips(
          pageRequest['targetRef'] as String,
          query: CommunityShipQuery.parse(
            (pageRequest['query'] as Map).cast<String, Object?>(),
          ),
        );
        final ship = parsed.ships.single;
        final image = await assembleCommunityShipImage(
          adapter,
          parsed.targetRef,
          ship.shipRef,
          expectedVersion: ship.imageVersion,
          checkCurrent: () {},
        );
        expect(image.version, ship.imageVersion);
        expect(
          image.bytes,
          base64Decode(_read('bridge-image-chunk.json')['data'] as String),
        );
        expect(parsed.imageFeatures!.read, isTrue);
        if (anonymous) {
          expect(ship.ownerCallsign, '');
          expect(adapter.ownerTarget(parsed.targetRef, ship), isNull);
        }
      },
    );
  }
  test('actual C lost report acknowledgement recovers after departure without old source or POST', () async {
    final reportRequest = _read('request-officialFleet-reportShipImage.json');
    final statusRequest = _read(
      'request-officialFleet-shipImageReportStatus.json',
    );
    final wire = ImageWire(
      capabilities: ['officialFleet.ships', ...imageNames],
      account: const BridgeAccountContext(
        environment: 'synthetic',
        authority: 'scm',
        subject: 'public-viewer-scene',
      ),
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
    wire.respond = (request) {
      switch (request.name) {
        case 'officialFleet.ships':
          return _read('bridge-public-page.json');
        case 'officialFleet.reportShipImage':
          expect(request.payload, reportRequest);
          return _read('bridge-report-unknown.json');
        case 'officialFleet.shipImageReportStatus':
          expect(request.payload, statusRequest);
          return _read('bridge-report-status.json');
        default:
          throw StateError('Unexpected replay command ${request.name}');
      }
    };
    await adapter.readShips(reportRequest['targetRef'] as String);
    final intent = CommunityShipReportIntent(
      targetRef: reportRequest['targetRef'] as String,
      shipRef: reportRequest['shipRef'] as String,
      version: reportRequest['version'] as String,
      requestId: reportRequest['requestId'] as String,
      reason: reportRequest['reason'] as String,
      details: reportRequest['details'] as String,
    );
    expect((await adapter.reportShipImage(intent)).status, 'unknown');
    wire.sourceChanges.value = null;
    expect((await adapter.checkShipReport(intent)).status, 'accepted');
    expect(
      wire.requests
          .where((r) => r.name == 'officialFleet.reportShipImage')
          .length,
      1,
    );
    expect(
      wire.requests
          .where((r) => r.name == 'officialFleet.shipImageReportStatus')
          .length,
      1,
    );
  });
  test('actual C owner positive save then retained old-scope images-only clear preserves strict requests', () async {
    final positive = _read('request-positive-images.json'),
        clear = _read('request-clear-images.json');
    final wire = ImageWire(
      capabilities: [
        'officialFleet.hangarSharing',
        'officialFleet.hangarSharingPage',
        'officialFleet.saveHangarSharing',
        ...imageNames,
      ],
      account: const BridgeAccountContext(
        environment: 'synthetic',
        authority: 'scm',
        subject: 'owner-editor-scene',
      ),
    );
    final adapter = BridgeOfficialFleetHangarSharing(wire.session);
    addTearDown(() async {
      await adapter.close();
      await wire.close();
    });
    var retained = false;
    wire.respond = (request) {
      if (request.name == 'officialFleet.hangarSharing') {
        expect(request.payload, _read('request-owner-editor.json'));
        return _read(
          retained
              ? 'bridge-old-scope-editor.json'
              : 'bridge-owner-editor.json',
        );
      }
      expect(request.name, 'officialFleet.saveHangarSharing');
      expect(request.payload, retained ? clear : positive);
      return _read(
        retained
            ? 'bridge-clear-result.json'
            : 'bridge-positive-images-result.json',
      );
    };
    final draft = await adapter.read(positive['sourceRef'] as String);
    expect(draft.allowImages, isTrue);
    expect(
      (await adapter.save(
        draft.editRef,
        draft.sourceRef,
        positive['strategy'] as String,
        (positive['selectedRefs'] as List).cast<String>(),
        includeImages: true,
      )).status,
      'accepted',
    );
    retained = true;
    final old = await adapter.read(clear['sourceRef'] as String);
    expect(old.canPublish, isFalse);
    expect(old.selectionKnown, isFalse);
    expect(old.canClearImages, isTrue);
    expect(
      (await adapter.save(
        old.editRef,
        old.sourceRef,
        'organizationPool',
        (positive['selectedRefs'] as List).cast<String>(),
        includeImages: true,
      )).status,
      'rejected',
    );
    expect(
      wire.requests
          .where((r) => r.name == 'officialFleet.saveHangarSharing')
          .length,
      1,
    );
    expect(
      (await adapter.clearImages(old.editRef, old.sourceRef!)).status,
      'accepted',
    );
    expect(
      wire.requests.any((r) => r.name == 'officialFleet.hangarSharingPage'),
      isFalse,
    );
    expect(
      wire.requests
          .where((r) => r.name == 'officialFleet.saveHangarSharing')
          .length,
      2,
    );
  });
}
