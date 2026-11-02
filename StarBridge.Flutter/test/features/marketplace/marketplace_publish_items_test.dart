import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/bridge_marketplace_listings_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish_widgets.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_slice4_test.dart' show preview;

/// Rows exactly as the Host's `search` projection returns them.
MarketRow hostItem(int id, String name, {String? quality, int categoryId = 11}) => {
  'id': id,
  'categoryId': categoryId,
  'itemName': name,
  'itemNameEn': 'Item $id',
  'thumbnailUrl': null,
  'sellOrderCount': 3,
  'buyOrderCount': 1,
  'qualityInfo': quality,
};

class LookupFixture implements MarketplaceListingsPort, MarketplaceListingLookup {
  final searches = <(String, int)>[];
  @override
  Future<MarketRow> read() async => {
    'rows': <Object>[],
    'total': 0,
    'items': [listingPickable(hostItem(1, '科力晶'))],
    'manifests': <Object>[],
    'locations': <Object>[],
  };
  @override
  Future<void> write(String operation, MarketRow input) async {}
  @override
  Future<MarketRow> nextPage(int page) async => {'rows': <Object>[]};
  @override
  Future<List<MarketRow>> categories() async => [
    {'id': 1, 'parentId': 0, 'name': '飞船'},
    {'id': 2, 'parentId': 0, 'name': '武器'},
    {'id': 21, 'parentId': 2, 'name': '步枪'},
  ];
  @override
  Future<List<MarketRow>> searchItems(String query, {int category = 0, int page = 1}) async {
    searches.add((query, category));
    return [
      if (category == 21) listingPickable(hostItem(7, 'P4-AR 步枪', categoryId: 21))
      else listingPickable(hostItem(1, '科力晶')),
    ];
  }
}

void main() {
  test('Host search rows become pickable names, counts and quality', () {
    final row = listingPickable(hostItem(9, '科力晶', quality: '{"min":0}'));
    expect(row['name'], '科力晶');
    expect(row['sellCount'], 3);
    expect(row['buyCount'], 1);
    expect(row['hasQuality'], isTrue);
    expect(listingPickable(hostItem(9, ''))['name'], 'Item 9');
    expect(listingPickable(hostItem(9, 'x'))['hasQuality'], isFalse);
  });

  testWidgets('item step lists real names, searches and browses categories', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = LookupFixture();
    final c = MarketplaceListingsController(port);
    await c.refresh();
    await tester.pumpWidget(
      preview(
        ListingPublishDialog(c, ListingDraft(), initialStep: 1),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('null'), findsNothing);
    expect(find.text('科力晶'), findsOneWidget);
    // Typing filters by the Chinese name.
    await tester.enterText(find.byType(TextField).first, '科力');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('科力晶'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    // Browse like 市场: the root expands in the tree, then pick its child.
    await tester.tap(find.text('武器'));
    await tester.pumpAndSettle();
    expect(find.text('步枪'), findsOneWidget);
    await tester.tap(find.text('步枪'));
    await tester.pumpAndSettle();
    expect(find.text('在「步枪」中搜索'), findsOneWidget);
    expect(port.searches.last.$2, 21);
    expect(find.text('P4-AR 步枪'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('a picked item survives route rebuilds and late search results', (
    tester,
  ) async {
    // Regression (user report 2026-10-20): the motion dialog route calls its
    // builder again, and the entry used to create a fresh draft in it, so
    // the pick vanished about a second after the click.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = LookupFixture();
    final c = MarketplaceListingsController(port);
    await c.refresh();
    late StateSetter rebuild;
    var builds = 0;
    await tester.pumpWidget(
      preview(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            builds++;
            // Like the route builder: a brand-new draft on every build.
            return ListingPublishDialog(c, ListingDraft(), initialStep: 1);
          },
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    bool picked(String name) => tester
        .widgetList<ListingPickTile>(find.byType(ListingPickTile))
        .any((t) => t.title == name && t.selected);
    await tester.tap(find.text('科力晶'));
    await tester.pumpAndSettle();
    expect(picked('科力晶'), isTrue);
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(builds, greaterThan(1));
    expect(picked('科力晶'), isTrue, reason: 'route rebuild keeps the pick');
    // A late search answer that still contains the item keeps it picked.
    await tester.enterText(find.byType(TextField).first, '科');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(picked('科力晶'), isTrue, reason: 'late results keep the pick');
    expect(find.byKey(const Key('publish-picked-hidden')), findsNothing);
    // Browsing elsewhere hides the tile but never drops the pick silently.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('武器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('步枪'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('publish-picked-hidden')), findsOneWidget);
    expect(find.textContaining('已选：科力晶'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('a slow base read never replaces search results', (tester) async {
    // Regression (user report 2026-10-20): searching 焦点 showed three items,
    // then the wizard's opening read answered and shrank the list to the one
    // item that already had listings.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = _SlowReadFixture();
    final c = MarketplaceListingsController(port);
    final opening = c.refresh();
    await tester.pumpWidget(
      preview(ListingPublishDialog(c, ListingDraft(), initialStep: 1), AppearanceMode.dark),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '焦点');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('焦点波'), findsNWidgets(3));
    port.read$.complete();
    await opening;
    await tester.pumpAndSettle();
    expect(find.textContaining('焦点波'), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}

class _SlowReadFixture extends LookupFixture {
  final read$ = Completer<void>();
  @override
  Future<MarketRow> read() async {
    await read$.future;
    return {
      'rows': <Object>[],
      'total': 0,
      'items': [listingPickable(hostItem(10, '焦点波-10'))],
      'manifests': <Object>[],
      'locations': <Object>[],
    };
  }

  @override
  Future<List<MarketRow>> searchItems(String query, {int category = 0, int page = 1}) async => [
    if (query.contains('焦点')) ...[
      listingPickable(hostItem(10, '焦点波-10')),
      listingPickable(hostItem(20, '焦点波-20')),
      listingPickable(hostItem(30, '焦点波-30')),
    ] else listingPickable(hostItem(1, '科力晶')),
  ];
}
