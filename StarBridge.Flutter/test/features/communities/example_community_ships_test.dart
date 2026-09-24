import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_catalog_ship_image.dart';
import 'package:starbridge_flutter/features/communities/community_member_banner.dart';
import 'package:starbridge_flutter/features/communities/community_ship_banner.dart';

import 'community_ships_test.dart' show shipRow;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

const target = '00000000000000000000000000000001';
const other = '00000000000000000000000000000002';

void main() {
  setUpAll(loadFonts);
  test(
    'ship subtitles use language-specific catalog facts, never internal IDs',
    () {
      final ship = CommunitySharedShip.parse(
        shipRow()
          ..['code'] = 'catalog-test'
          ..['englishName'] = 'Fixture Ship'
          ..['manufacturer'] = 'Fixture Builder',
      );
      expect(ship.subtitleFor('zh'), 'Fixture Ship');
      expect(ship.subtitleFor('en'), 'Fixture Builder');
      final missing = CommunitySharedShip.parse(
        shipRow()..['code'] = 'catalog-test',
      );
      expect(missing.subtitleFor('zh'), isNull);
      expect(missing.subtitleFor('en'), isNull);
    },
  );
  test('example library queries all rows before coherent paging', () async {
    final port = ExampleCommunities();
    addTearDown(port.close);
    final page = await port.readShips(target);
    expect(page.totalCount, 25);
    expect(page.ships, hasLength(20));
    final next = await port.readShips(
      target,
      offset: 20,
      revision: page.revision,
    );
    expect(next.ships, hasLength(5));
    expect({
      ...page.ships.map((s) => s.shipRef),
      ...next.ships.map((s) => s.shipRef),
    }, hasLength(25));
    final filtered = await port.readShips(
      target,
      query: CommunityShipQuery(text: 'vulture'),
    );
    expect(filtered.ships.every((s) => s.code == 'vulture'), isTrue);
    expect(filtered.matchedCount, 6);
    final concept = await port.readShips(
      target,
      query: CommunityShipQuery(filter: 'concept'),
    );
    expect(concept.matchedCount, 6);
    expect(concept.ships.every((s) => s.catalogStatus == '概念'), isTrue);
    final english = await port.readShips(
      target,
      query: CommunityShipQuery(culture: 'en-US'),
    );
    expect(english.ships.first.catalogSpec, 'large');
    expect(english.ships.first.catalogPriceUsd, isNull);
  });

  test(
    'query and organization changes cannot reuse a page revision or instance',
    () async {
      final port = ExampleCommunities();
      addTearDown(port.close);
      final page = await port.readShips(target);
      final second = await port.readShips(other);
      expect(
        second.ships
            .map((s) => s.shipRef)
            .toSet()
            .intersection(page.ships.map((s) => s.shipRef).toSet()),
        isEmpty,
      );
      await expectLater(
        port.readShips(other, revision: page.revision),
        throwsA(isA<CommunityFailure>()),
      );
      await expectLater(
        port.readShips(
          target,
          revision: page.revision,
          query: CommunityShipQuery(sort: 'name'),
        ),
        throwsA(isA<CommunityFailure>()),
      );
      await port.execute('leave', target);
      await expectLater(
        port.readShips(target),
        throwsA(isA<CommunityFailure>()),
      );
      expect((await port.readShips(other)).totalCount, 25);
      await port.close();
      expect(port.shipsAvailable, isFalse);
      await expectLater(
        port.readShips(other),
        throwsA(isA<CommunityFailure>()),
      );
    },
  );

  test('catalog artwork accepts only bundled ship paths and older payloads remain valid', () {
    expect(CommunitySharedShip.parse(shipRow()).catalogImageAsset, isNull);
    for (final path in [
      'https://example.invalid/a.png',
      '../secret.png',
      'C:/secret.png',
      'assets/ships/../secret.png',
    ]) {
      expect(
        CommunitySharedShip.parse(shipRow()..['catalogImageAsset'] = path)
            .catalogImageAsset,
        isNull,
      );
    }
    expect(
      CommunitySharedShip.parse(
        shipRow()..['catalogImageAsset'] = 'assets/ships/carrack.png',
      ).catalogImageAsset,
      'assets/ships/carrack.png',
    );
  });

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [420.0, 1200.0]) {
      testWidgets(
        'example ships via organization entry ${locale.toLanguageTag()} $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final port = ExampleCommunities();
          addTearDown(port.close);
          await tester.pumpWidget(host(port, locale, target: target));
          await tester.pumpAndSettle();
          // Scrollbar has its own gutter, outside the member cards.
          final banner = find.byType(CommunityMemberBanner).first;
          final list = find
              .ancestor(of: banner, matching: find.byType(ListView))
              .first;
          expect(
            tester.getBottomRight(list).dx - tester.getBottomRight(banner).dx,
            greaterThanOrEqualTo(16),
          );
          await tester.tap(
            find.byKey(const ValueKey('community-section-ships')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CommunityShipsPanel), findsOneWidget);
          expect(find.byType(CommunityCatalogShipImage), findsWidgets);
          expect(find.text('1–20 / 25'), findsOneWidget);
          final filter = find.byKey(
            const ValueKey('community-ship-filter-concept'),
          );
          // Compact windows scroll the ship pane vertically before its
          // independent horizontal filter strip can receive a drag.
          await tester.ensureVisible(
            find.byKey(const ValueKey('community-ship-filters')),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            filter,
            180,
            scrollable: find.descendant(
              of: find.byKey(const ValueKey('community-ship-filters')),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(filter);
          await tester.pumpAndSettle();
          await tester.tap(filter);
          await tester.pumpAndSettle();
          expect(find.text('1–6 / 6'), findsOneWidget);
          final detailButton = find
              .descendant(
                of: find.byType(CommunityShipsPanel),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is OutlinedButton &&
                      widget.key is ValueKey<String> &&
                      (widget.key as ValueKey<String>).value.startsWith(
                        'community-ship-details-',
                      ),
                ),
              )
              .first;
          await tester.tap(detailButton);
          await tester.pumpAndSettle();
          expect(find.byType(CommunityShipDetailDialog), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(CommunityShipDetailDialog),
              matching: find.byType(CommunityCatalogShipImage),
            ),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.flag_outlined), findsNothing);
          final detailArtwork = tester.widget<CommunityCatalogShipImage>(
            find.descendant(
              of: find.byType(CommunityShipDetailDialog),
              matching: find.byType(CommunityCatalogShipImage),
            ),
          );
          expect(detailArtwork.asset, startsWith('assets/ships/catalog-'));
          expect(detailArtwork.asset, isNot(contains('catalog-square-')));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'organization ship sharing entry renders and saves example choices',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = ExampleCommunities();
      addTearDown(port.close);
      await tester.pumpWidget(
        host(port, const Locale('zh', 'CN'), target: target),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('community-section-ships')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.share_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find
            .ancestor(
              of: find.byType(AlertDialog),
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File('build/community-hangar-sharing-review.png')
            .writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.text('保存共享范围'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await port.readHangarSharing()).options
            .where((r) => r.selected)
            .length,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('render complete example ships page', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = ExampleCommunities();
    addTearDown(port.close);
    await tester.pumpWidget(
      host(port, const Locale('zh', 'CN'), target: target),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-section-ships')));
    await tester.pumpAndSettle();
    final banner = find.byType(CommunityShipBanner).first;
    expect(tester.getSize(banner).height, lessThanOrEqualTo(72));
    final cells = tester.widget<CommunityShipBanner>(banner);
    final y = tester.getCenter(find.byWidget(cells.identity)).dy;
    for (final cell in [
      cells.spec,
      cells.status,
      cells.price,
      cells.role,
      cells.owner,
      cells.importedAt,
      cells.action,
    ]) {
      expect(tester.getCenter(find.byWidget(cell)).dy, closeTo(y, 1));
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('workspace-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final output = File('build/community-ships-example-review.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.byWidget(cells.action));
    await tester.pumpAndSettle();
    final artwork = tester.widget<CommunityCatalogShipImage>(
      find.descendant(
        of: find.byType(CommunityShipDetailDialog),
        matching: find.byType(CommunityCatalogShipImage),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        AssetImage(artwork.asset!),
        tester.element(find.byType(CommunityShipDetailDialog)),
        onError: (_, _) {},
      ),
    );
    await tester.pumpAndSettle();
    final detailBoundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.byType(CommunityShipDetailDialog),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    await tester.runAsync(() async {
      final image = await detailBoundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('build/community-ship-landscape-review.png')
          .writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
