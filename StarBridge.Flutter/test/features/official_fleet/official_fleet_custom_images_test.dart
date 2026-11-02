import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_port.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_shared_ships.dart';

import 'official_fleet_image_test_support.dart';

void main() {
  late ImageWire wire;
  late BridgeOfficialFleetSharedShips adapter;
  setUp(() {
    wire = ImageWire(capabilities: ['officialFleet.ships', ...imageNames]);
    adapter = BridgeOfficialFleetSharedShips(
      wire.session,
      sourceRef: () => wire.sourceChanges.value,
      sourceChanges: wire.sourceChanges,
    );
    wire.respond = (r) => r.name == 'officialFleet.ships'
        ? imagePage(r.payload)
        : imageChunk(r.payload);
  });
  tearDown(() async {
    await adapter.close();
    await wire.close();
  });

  test(
    'negotiated image uses common assembly and exact opaque/version request',
    () async {
      final page = await adapter.readShips(ref(9));
      final model = CommunityShipDetailController(adapter, page, ref(1));
      addTearDown(model.dispose);
      await model.load();
      expect(model.image!.bytes, pngBytes);
      expect(model.image!.focusX, .3);
      expect(model.image!.zoom, 1.4);
      expect(model.canReportImage, isTrue);
      final request = wire.requests.singleWhere(
        (r) => r.name == 'officialFleet.shipImage',
      );
      expect(request.payload, {
        'schemaVersion': 1,
        'targetRef': ref(9),
        'shipRef': ref(1),
        'offset': 0,
        'version': hash(10),
      });
      expect(
        wire.requests.any((r) => r.name.startsWith('communities.')),
        isFalse,
      );
      await model.load(background: true);
      expect(
        wire.requests.where((r) => r.name == 'officialFleet.shipImage').length,
        1,
      );
      wire.sourceChanges.value = 'officialFleet:8';
      await Future<void>.delayed(Duration.zero);
      expect(model.ship, isNull);
      expect(model.image, isNull);
      expect(adapter.shipImageAvailable, isFalse);
    },
  );
  test('actual old page with all callables stays catalog only', () async {
    wire.respond = (r) => imagePage(r.payload, features: null, hasImage: false);
    final page = await adapter.readShips(ref(9));
    final model = CommunityShipDetailController(adapter, page, ref(1));
    addTearDown(model.dispose);
    await model.load();
    expect(page.imageFeatures, isNull);
    expect(model.image, isNull);
    expect(adapter.shipImageAvailable, isFalse);
    expect(adapter.shipReportAvailable, isFalse);
    expect(
      wire.requests.every(
        (r) =>
            r.name == 'account.getCurrent' || r.name == 'officialFleet.ships',
      ),
      isTrue,
    );
  });
  test('restricted holder stays anonymous while an explicit image grant remains readable', () async {
    wire.respond = (r) {
      if (r.name != 'officialFleet.ships') return imageChunk(r.payload);
      final page = imagePage(r.payload);
      return {
        ...page,
        'ships': [
          {...(page['ships'] as List).single as Map, 'ownerCallsign': ''},
        ],
        'owners': [
          {
            'ownerMemberRef': ref(2),
            'profileReference': null,
            'avatarImageData': null,
            'avatarVersion': null,
          },
        ],
      };
    };
    final page = await adapter.readShips(ref(9));
    final model = CommunityShipDetailController(adapter, page, ref(1));
    addTearDown(model.dispose);
    await model.load();
    expect(model.ship!.ownerCallsign, '');
    expect(adapter.ownerTarget(ref(9), model.ship!), isNull);
    expect(model.image!.bytes, pngBytes);
    expect(model.canReportImage, isTrue);
  });
  test(
    'malformed features and inconsistent versions fail closed and clear access',
    () async {
      for (final mutate
          in <Map<String, Object?> Function(Map<String, Object?>)>[
            (p) => {
              ...p,
              'imageFeatures': {'protocolVersion': 1, 'read': true},
            },
            (p) => {
              ...p,
              'imageFeatures': {...imageFeatures, 'upload': 'true'},
            },
            (p) => {
              ...p,
              'ships': [
                {...(p['ships'] as List).single as Map, 'imageVersion': null},
              ],
            },
            (p) => {
              ...p,
              'ships': [
                {
                  ...(p['ships'] as List).single as Map,
                  'hasCustomImage': false,
                },
              ],
            },
            (p) => {
              ...p,
              'imageFeatures': {...imageFeatures, 'protocolVersion': 2},
            },
          ]) {
        wire.respond = (r) => imagePage(r.payload);
        await adapter.readShips(ref(9));
        expect(adapter.shipImageAvailable, isTrue);
        wire.respond = (r) => mutate(imagePage(r.payload));
        await expectLater(
          adapter.readShips(ref(9)),
          throwsA(isA<CommunityFailure>()),
        );
        expect(adapter.shipImageAvailable, isFalse);
        expect(adapter.shipReportAvailable, isFalse);
      }
    },
  );
  test(
    'features and actual callables independently fence custom image operations',
    () async {
      wire.respond = (r) =>
          imagePage(r.payload, features: {...imageFeatures, 'read': false});
      await adapter.readShips(ref(9));
      expect(adapter.shipImageAvailable, isFalse);
      expect(
        () => adapter.readShipImage(ref(9), ref(1), offset: 0),
        throwsA(isA<CommunityFailure>()),
      );
      wire.session.acceptHostCapabilities([
        'officialFleet.ships',
        'officialFleet.shipImage',
      ]);
      await Future<void>.delayed(Duration.zero);
      wire.respond = (r) => imagePage(r.payload);
      await adapter.readShips(ref(9));
      expect(adapter.shipImageAvailable, isTrue);
      expect(adapter.shipReportAvailable, isFalse);
      expect(
        wire.requests.where((r) => r.name == 'officialFleet.shipImage'),
        isEmpty,
      );
    },
  );
  test('different chunk version cannot publish old or partial bytes', () async {
    wire.respond = (r) => r.name == 'officialFleet.ships'
        ? imagePage(r.payload)
        : {...imageChunk(r.payload), 'version': hash(99)};
    final page = await adapter.readShips(ref(9));
    final model = CommunityShipDetailController(adapter, page, ref(1));
    addTearDown(model.dispose);
    await model.load();
    expect(model.image, isNull);
    expect(model.imageError, 'dataInvalid');
    expect(model.canReportImage, isFalse);
  });
  test(
    'submitted unknown receipt survives source loss and never replays POST',
    () async {
      final receipt = <String, Object?>{};
      wire.respond = (r) {
        if (r.name == 'officialFleet.ships') return imagePage(r.payload);
        if (r.name == 'officialFleet.reportShipImage') {
          receipt.addAll(r.payload);
          return {...r.payload, 'status': 'unknown', 'error': 'outcomeUnknown'};
        }
        expect(r.name, 'officialFleet.shipImageReportStatus');
        expect(r.payload, {
          'schemaVersion': 1,
          'requestId': receipt['requestId'],
        });
        return {...receipt, 'status': 'accepted', 'error': null};
      };
      await adapter.readShips(ref(9));
      final model = CommunityShipReportController(
        adapter,
        ref(9),
        ref(1),
        hash(10),
      );
      addTearDown(model.dispose);
      model.edit('inappropriate_content', 'Fixture report');
      await model.submit();
      expect(model.unknown, isTrue);
      wire.sourceChanges.value = null;
      model.retireSource();
      await model.check();
      expect(model.accepted, isTrue);
      expect(model.editable, isFalse);
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
    },
  );
  test(
    'generation retirement rejects a late status and emits receipt retirement',
    () async {
      final started = Completer<void>(), finish = Completer<void>();
      final intent = CommunityShipReportIntent(
        targetRef: ref(9),
        shipRef: ref(1),
        version: hash(10),
        requestId: ref(100),
        reason: 'inappropriate_content',
        details: '',
      );
      var retired = 0;
      final sub = adapter.reportReceiptRetirements.listen((_) => retired++);
      addTearDown(sub.cancel);
      wire.respond = (r) async {
        started.complete();
        await finish.future;
        return {
          'schemaVersion': 1,
          ...intent.toPayload(),
          'status': 'accepted',
          'error': null,
        };
      };
      final pending = adapter.checkShipReport(intent);
      await started.future;
      wire.session.advanceGeneration(2);
      finish.complete();
      expect((await pending).status, 'unknown');
      await Future<void>.delayed(Duration.zero);
      expect(retired, greaterThan(0));
      expect(
        wire.requests.where((r) => r.name == 'officialFleet.reportShipImage'),
        isEmpty,
      );
    },
  );
}
