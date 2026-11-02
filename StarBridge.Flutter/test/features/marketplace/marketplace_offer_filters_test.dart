import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_test.dart' show FixturePort, app;

/// Records which options each offers read carried.
class RecordingPort extends FixturePort {
  final offers = <(int side, Map<String, String> options)>[];
  @override
  Future<MarketRead> read(
    String operation, {
    int id = 0,
    String keyword = '',
    int category = 0,
    int side = 1,
    int page = 1,
    String language = 'CN',
    Map<String, String> options = const {},
  }) {
    if (operation == 'offers') offers.add((side, Map.of(options)));
    return super.read(
      operation,
      id: id,
      keyword: keyword,
      category: category,
      side: side,
      page: page,
      language: language,
      options: options,
    );
  }
}

void main() {
  test('offer filters go to SCM for both sides and reset per item', () async {
    final port = RecordingPort();
    final c = MarketplaceController(port);
    await c.openItem(1);
    expect(port.offers.map((o) => o.$2), everyElement(isEmpty));
    port.offers.clear();

    await c.setOfferFilter('creatorStatus', '2');
    expect(port.offers.map((o) => o.$1).toSet(), {0, 1});
    expect(port.offers.map((o) => o.$2), everyElement({'creatorStatus': '2'}));
    port.offers.clear();

    await c.setOfferFilter('minQuality', '600');
    await c.setOfferFilter(
      'locationId',
      '8',
      location: {'id': 8, 'name': '炽天使空间站'},
    );
    expect(c.offerLocation?['name'], '炽天使空间站');
    port.offers.clear();
    await c.moreOffers(false);
    expect(port.offers.single.$2, {
      'creatorStatus': '2',
      'minQuality': '600',
      'locationId': '8',
    });
    port.offers.clear();

    // Explicit direction overrides the side default.
    expect(c.offerSortOrder(false), 'asc');
    expect(c.offerSortOrder(true), 'desc');
    await c.setOfferFilter('sortOrder', 'desc');
    expect(c.offerSortOrder(false), 'desc');
    expect(port.offers.every((o) => o.$2['sortOrder'] == 'desc'), isTrue);
    port.offers.clear();

    await c.clearOfferFilters();
    expect(c.offerFilters, isEmpty);
    expect(c.offerLocation, isNull);
    expect(port.offers.map((o) => o.$2), everyElement(isEmpty));
    port.offers.clear();

    await c.setOfferFilter('creatorStatus', '1');
    port.offers.clear();
    await c.openItem(2);
    expect(c.offerFilters, isEmpty);
    expect(port.offers.map((o) => o.$2), everyElement(isEmpty));
    c.dispose();
  });

  testWidgets('filter row drives reads and shows the chosen state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = RecordingPort();
    final c = MarketplaceController(port);
    await tester.pumpWidget(
      app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
    );
    await tester.pumpAndSettle();
    await c.openItem(1);
    await tester.pumpAndSettle();
    port.offers.clear();

    await tester.tap(find.text('游戏中'));
    await tester.pumpAndSettle();
    expect(port.offers.map((o) => o.$2), everyElement({'creatorStatus': '2'}));
    expect(find.text('全部清除'), findsOneWidget);

    await tester.tap(find.text('品质 ≥'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('≥ 600'));
    await tester.pumpAndSettle();
    expect(find.text('品质 ≥ 600'), findsOneWidget);
    expect(c.offerFilters['minQuality'], '600');

    // Price direction now lives on the 单价 column header (↑ default for sell).
    expect(find.text('↑'), findsOneWidget);
    await tester.tap(find.text('单价'));
    await tester.pumpAndSettle();
    expect(find.text('↓'), findsOneWidget);
    expect(c.offerFilters['sortOrder'], 'desc');

    await tester.tap(find.text('全部清除'));
    await tester.pumpAndSettle();
    expect(c.offerFilters, isEmpty);
    expect(find.text('全部清除'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
