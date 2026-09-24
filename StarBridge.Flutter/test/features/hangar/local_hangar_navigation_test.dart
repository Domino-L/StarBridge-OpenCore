import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/hangar_feature.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/shared/ships/catalog_vehicle_icon.dart';
import 'package:starbridge_flutter/shared/ships/ship_reviewed_display.dart';

import 'hangar_reader_test.dart' as fixtures;

void main() {
  testWidgets('local inventory can be prepared before the page is mounted', (tester) async {
    final account = createAccountModule(
      InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
    );
    await account.initialize();
    addTearDown(account.dispose);
    final port = _Port();
    final feature = createHangarFeature(
      account,
      () => fixtures.PreviewFake(),
      localFactory: () => port,
    );
    expect(feature.prefetch, isNotNull);
    final pending = feature.prefetch!();
    expect(port.reads, hasLength(1));
    port.reads.single.complete(
      const LocalHangarSnapshot(revision: 0, ships: []),
    );
    await pending;
    await feature.prefetch!();
    expect(port.reads, hasLength(1));
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(fixtures.app(Builder(builder: feature.buildDestination)));
      expect(find.text('正在读取本机机库…'), findsNothing);
      await tester.pumpWidget(fixtures.app(const SizedBox()));
    }
    expect(port.reads, hasLength(1));
    await account.logout();
    await feature.prefetch!();
    expect(port.reads, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'returning to personal hangar immediately retains saved inventory',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      await account.initialize();
      addTearDown(account.dispose);
      final port = _Port();
      var creations = 0;
      final feature = createHangarFeature(
        account,
        () => fixtures.PreviewFake(),
        localFactory: () {
          creations++;
          return port;
        },
      );
      Widget page() => fixtures.app(Builder(builder: feature.buildDestination));
      await tester.pumpWidget(page());
      port.reads.single.complete(
        const LocalHangarSnapshot(
          revision: 1,
          ships: [
            LocalHangarShip(
              id: 'test',
              title: 'Saved Ship',
              display: ShipReviewedDisplay(
                domain: 'utility',
                category: 'logistics',
                sizeClass: 'small',
                iconKey: 'utility-mpuv-tractor',
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved Ship'), findsOneWidget);
      await tester.pumpWidget(fixtures.app(const SizedBox()));
      await tester.pumpWidget(page());
      expect(find.text('Saved Ship'), findsOneWidget);
      expect(port.reads, hasLength(1));
      expect(creations, 1);
      // MPUV motion lasts longer than the old 3-second cache sentinel.
      final motion =
          tester
                  .widget<CatalogVehicleIcon>(find.byType(CatalogVehicleIcon))
                  .motion!
              as Animation<double>;
      expect(motion.value, 1);
      expect((motion as AnimationController).isAnimating, isFalse);
      await tester.tap(find.byKey(const Key('local-hangar-refresh')));
      await tester.pump();
      expect(port.reads, hasLength(2));
      expect(find.text('Saved Ship'), findsOneWidget);
      expect(find.text('正在读取本机机库…'), findsNothing);
      port.reads.last.completeError(StateError('synthetic read failure'));
      await tester.pumpAndSettle();
      expect(find.text('Saved Ship'), findsOneWidget);
      await tester.pumpWidget(fixtures.app(const SizedBox()));
      await account.logout();
      await tester.pumpAndSettle();
      await account.beginLogin();
      await tester.pumpAndSettle();
      await tester.pumpWidget(page());
      expect(find.text('Saved Ship'), findsNothing);
      expect(port.reads, hasLength(3));
      expect(creations, 2);
      port.reads.last.complete(
        const LocalHangarSnapshot(revision: 0, ships: []),
      );
      await tester.pumpAndSettle();
      expect(find.text('尚未保存机库'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _Port implements LocalHangarPort {
  final reads = <Completer<LocalHangarSnapshot>>[];
  @override
  Future<LocalHangarSnapshot> read() {
    final result = Completer<LocalHangarSnapshot>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => throw UnimplementedError();
}
