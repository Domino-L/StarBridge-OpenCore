import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ships_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_copy.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics.dart';
import 'package:starbridge_flutter/features/communities/community_ship_statistics_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import '../friends/social_layout_test.dart' show loadFonts;
import 'official_fleet_hangar_sharing_test.dart' show host;
import 'official_fleet_shared_ships_test.dart' show Harness, ref, ship;

void main() {
  setUpAll(loadFonts);
  for (final code in ['communities.readUnavailable', 'communities.unavailable']) {
    for (final background in [false, true]) {
      test('$code clears presentation and permits retry ($background)', () async {
        final h = Harness();
        addTearDown(h.close);
        final model = CommunityShipsController(h.adapter, ref(9));
        addTearDown(model.dispose);
        await model.load();
        final old = model.page!.ships.single;
        model.selectedShipRef = old.shipRef;
        h.error = code;
        await (background ? model.refreshVisible() : model.load());
        expect(model.error, 'readUnavailable');
        expect(model.invalidated, isFalse);
        expect(model.page, isNull);
        expect(model.pages, isEmpty);
        expect(model.statistics, isNull);
        expect(model.selectedShipRef, isNull);
        expect(h.adapter.ownerTarget(ref(9), old), isNull);
        expect(h.adapter.shipImageAvailable, isFalse);
        h.error = null;
        await model.load();
        expect(model.page!.ships, hasLength(1));
        expect(model.error, isNull);
      });
    }
  }

  for (final change in ['source', 'epoch']) {
    test('$change takes precedence over a late read failure', () async {
      final h = Harness();
      addTearDown(h.close);
      h.error = 'communities.readUnavailable';
      h.hold = Completer<void>();
      final pending = h.adapter.readShips(ref(9));
      final rejected = expectLater(
        pending,
        throwsA(isA<CommunityFailure>().having(
          (error) => error.code, 'code', 'identityUnavailable',
        )),
      );
      for (var i = 0; i < 20 &&
          !h.requests.any((r) => r.name == 'officialFleet.ships'); i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.requests.any((r) => r.name == 'officialFleet.ships'), isTrue);
      if (change == 'source') {
        h.source.value = 'officialFleet:8';
      } else {
        h.session.advanceGeneration(2);
      }
      h.hold!.complete();
      await rejected;
    });
  }

  test('statistics read failures keep the read failure code', () async {
    final h = Harness()..error = 'communities.readUnavailable';
    addTearDown(h.close);
    await expectLater(
      readCommunityShipStatistics(h.adapter, ref(9), 'zh-CN', checkCurrent: () {}),
      throwsA(isA<CommunityFailure>().having(
        (error) => error.code, 'code', 'readUnavailable',
      )),
    );
  });

  testWidgets('bridge timeout clears rows without invalidating the account', (tester) async {
    final h = Harness();
    addTearDown(h.close);
    final model = CommunityShipsController(h.adapter, ref(9));
    addTearDown(model.dispose);
    await model.load();
    h.hold = Completer<void>();
    final pending = model.refreshVisible();
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await pending;
    expect(model.page, isNull);
    expect(model.error, 'readUnavailable');
    expect(model.invalidated, isFalse);
    h.hold!.complete();
    await tester.pump();
  });

  testWidgets('a later statistics page failure clears the displayed library', (tester) async {
    final h = Harness();
    addTearDown(h.close);
    h.mutate = (page) {
      if (page['offset'] != 0) h.error = 'communities.readUnavailable';
      return {
        ...page,
        'totalCount': 21,
        'matchedCount': 21,
        'next': page['offset'] == 0 ? 20 : null,
        'ships': [
          for (var i = 0; i < (page['offset'] == 0 ? 20 : 1); i++)
            {...ship(), 'shipRef': ref(100 + i)},
        ],
      };
    };
    final model = CommunityShipsController(h.adapter, ref(9));
    addTearDown(model.dispose);
    await model.load();
    expect(model.page!.ships, hasLength(20));
    var failures = 0;
    await tester.pumpWidget(host(CommunityShipStatisticsPanel(
      port: h.adapter,
      targetRef: ref(9),
      culture: 'zh-CN',
      firstPage: model.page,
      onReadUnavailable: () {
        failures++;
        model.readUnavailable();
      },
    ), locale: const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    expect(failures, 1);
    expect(model.error, 'readUnavailable');
    expect(model.invalidated, isFalse);
    expect(model.pages, isEmpty);
    expect(model.statistics, isNull);
    expect(find.text('Bridge Pilot'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('a failed read revokes previously advertised image features', () async {
    final h = Harness();
    addTearDown(h.close);
    h.session.acceptHostCapabilities(const [
      'officialFleet.ships', 'officialFleet.shipImage',
    ]);
    await Future<void>.delayed(Duration.zero);
    h.mutate = (page) => {
      ...page,
      'imageFeatures': {
        'protocolVersion': 1, 'read': true, 'upload': false,
        'report': false, 'reduce': false,
      },
    };
    await h.adapter.readShips(ref(9));
    expect(h.adapter.shipImageAvailable, isTrue);
    h.error = 'communities.readUnavailable';
    await expectLater(h.adapter.readShips(ref(9)),
        throwsA(isA<CommunityFailure>().having(
          (error) => error.code, 'code', 'readUnavailable',
        )));
    expect(h.adapter.shipImageAvailable, isFalse);
  });

  for (final (locale, copy) in [
    (const Locale('zh', 'CN'), '读取共享舰船失败，请稍后重试。'),
    (const Locale('zh', 'TW'), '讀取共享艦船失敗，請稍後重試。'),
    (const Locale('en', 'US'), 'Shared ships could not be loaded. Try again later.'),
  ]) {
    testWidgets('read failure and identity copy stay distinct in $locale', (tester) async {
      final h = Harness();
      addTearDown(h.close);
      final model = CommunityShipsController(h.adapter, ref(9));
      addTearDown(model.dispose);
      var back = 0, membership = 0;
      await tester.pumpWidget(host(
        CommunityShipsPanel(
          port: h.adapter,
          controller: model,
          targetRef: ref(9),
          name: 'Fleet',
          onBack: () { back++; },
          onRefreshMembership: () async { membership++; },
        ),
        locale: locale,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Bridge Pilot'), findsWidgets);
      h.error = 'communities.readUnavailable';
      await tester.tap(find.byKey(const Key('community-ships-refresh')));
      await tester.pumpAndSettle();
      expect(find.text(copy), findsOneWidget);
      expect(find.text('Bridge Pilot'), findsNothing);
      expect(model.invalidated, isFalse);
      final before = h.requests.where((r) => r.name == 'officialFleet.ships').length;
      h.error = null;
      await tester.tap(find.byKey(const Key('community-ships-refresh')));
      await tester.pumpAndSettle();
      expect(h.requests.where((r) => r.name == 'officialFleet.ships').length,
          greaterThan(before));
      expect(find.text('Bridge Pilot'), findsWidgets);
      expect(back, 0);
      expect(membership, 0);
      h.error = 'communities.identityUnavailable';
      await tester.tap(find.byKey(const Key('community-ships-refresh')));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(CommunityShipsPanel));
      expect(find.text(communityShipsText(context, 'identityUnavailable')), findsOneWidget);
      expect(find.text(copy), findsNothing);
      expect(model.invalidated, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('ordinary community unavailable still retains rows on refresh', () async {
    final h = Harness();
    addTearDown(h.close);
    final page = await h.adapter.readShips(ref(9));
    final port = _CommunityPort(page);
    final model = CommunityShipsController(port, ref(9));
    addTearDown(model.dispose);
    await model.load();
    port.fail = true;
    await model.refreshVisible();
    expect(model.error, 'unavailable');
    expect(model.page, same(page));
    expect(model.invalidated, isFalse);
  });
}

final class _CommunityPort implements CommunityShipsPort {
  _CommunityPort(this.page);
  final CommunityShipsPage page;
  bool fail = false;
  @override
  bool get shipsAvailable => true;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<CommunityShipsPage> readShips(String targetRef, {
    int offset = 0, String? revision, CommunityShipQuery? query,
  }) async {
    if (fail) throw const CommunityFailure('unavailable');
    return page;
  }
}
