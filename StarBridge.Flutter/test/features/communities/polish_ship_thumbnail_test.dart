import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_catalog_ship_image.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/shared/remote_image.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';
import 'package:starbridge_flutter/shared/ships/scm_ship_thumbnail.dart';

import '../official_fleet/polish_evidence_refresh_test.dart' show app;
import 'bridge_communities_test.dart' show CommunityHarness;

class _Mode extends ChangeNotifier implements ConnectionModeControl {
  @override
  ConnectionModeSnapshot get snapshot => const ConnectionModeSnapshot();
  @override
  bool get allowsOnlineTraffic => true;
  @override
  bool get busy => false;
  @override
  bool get failed => false;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
}

void main() {
  testWidgets(
    'bundled catalogue art never starts the public thumbnail lookup',
    (tester) async {
      var reads = 0;
      await tester.pumpWidget(
        app(
          ShipThumbnailScope(
            read: (_) async {
              reads++;
              return 'https://media.example.test/ship.png';
            },
            child: const CommunityCatalogShipImage(
              asset: 'assets/achievements/collection-earned.png',
              model: 'ANVL_Carrack',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(find.byType(ScmShipThumbnail), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'absent/failed bundled artwork uses controlled ship image; no thumbnail keeps placeholder',
    (tester) async {
      for (final asset in <String?>[null, 'assets/ships/missing.png']) {
        final models = <String>[];
        await tester.pumpWidget(
          app(
            ShipThumbnailScope(
              read: (model) async {
                models.add(model);
                return 'https://media.example.test/ship.png';
              },
              child: CommunityCatalogShipImage(
                asset: asset,
                model: 'ANVL_Carrack',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(models, ['ANVL_Carrack']);
        final image = tester.widget<RemoteImage>(find.byType(RemoteImage));
        expect(image.kind, RemoteImageResourceKind.ship);
        expect(image.followRedirects, isFalse);
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpWidget(
        app(
          ShipThumbnailScope(
            read: (_) async => null,
            child: const CommunityCatalogShipImage(
              asset: null,
              model: 'unknown',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RemoteImage), findsNothing);
      expect(find.text('尚无可用舰船图片。'), findsOneWidget);
    },
  );

  testWidgets('retired model lookup cannot repaint another ship', (
    tester,
  ) async {
    final first = Completer<String?>(), second = Completer<String?>();
    Future<String?> read(String model) =>
        model == 'first' ? first.future : second.future;
    Widget show(String model) => app(
      ShipThumbnailScope(
        read: read,
        child: CommunityCatalogShipImage(asset: null, model: model),
      ),
    );
    await tester.pumpWidget(show('first'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(show('second'));
    await tester.pump();
    second.complete('https://media.example.test/second.png');
    await tester.pumpAndSettle();
    first.complete('https://media.example.test/first.png');
    await tester.pumpAndSettle();
    expect(
      tester.widget<RemoteImage>(find.byType(RemoteImage)).source,
      'https://media.example.test/second.png',
    );
  });

  for (final available in [true, false]) {
    testWidgets(
      'bridge model lookup is scoped, coalesced and capability gated: $available',
      (tester) async {
        final host = CommunityHarness(
          capabilities: available ? ['ships.specifications'] : [],
          responses: {
            'ships.specifications': {
              'schemaVersion': 1,
              'specifications': {
                'state': 'ready',
                'thumbnailUrl': 'https://media.example.test/ship.png',
              },
            },
          },
        );
        addTearDown(host.close);
        final mode = _Mode();
        final loader = RemoteImageLoader(
          mode: mode,
          createClient: () =>
              throw StateError('Tests must not create a network client'),
        );
        addTearDown(() async {
          await loader.retireAsync();
          loader.dispose();
          mode.dispose();
        });
        ShipThumbnailReader? read;
        await tester.pumpWidget(
          app(
            RemoteImageScope(
              loader: loader,
              child: BridgeShipThumbnailScope(
                session: host.session,
                child: Builder(
                  builder: (context) {
                    read = ShipThumbnailScope.of(context)!.read;
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final reading = Future.wait([read!('Carrack'), read!('Carrack')]);
        await tester.pumpAndSettle();
        final results = await reading;
        expect(
          results,
          available
              ? List.filled(2, 'https://media.example.test/ship.png')
              : [null, null],
        );
        expect(
          host.requests.where((r) => r.name == 'ships.specifications'),
          hasLength(available ? 1 : 0),
        );
        if (available) expect(host.requests.last.payload['model'], 'Carrack');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
