import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';

import 'marketplace_slice4_test.dart' show ListingsFixture, preview;

void main() {
  testWidgets('unavailable own trading hours offer SCM without claiming unset', (tester) async {
    final c = MarketplaceListingsController(ListingsFixture());
    var opened = false;
    await tester.pumpWidget(preview(ListingPublishDialog(
      c, ListingDraft(item: {'id': 1, 'name': 'Fixture'}), initialStep: 2,
      editProfile: () => opened = true,
    ), AppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('请到 SCM 查看或设置交易时段'), findsOneWidget);
    expect(find.text('未设置'), findsNothing);
    await tester.ensureVisible(find.text('打开 SCM'));
    await tester.tap(find.text('打开 SCM'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  test('grouped prices use the same parser for validation and submission', () {
    final draft = ListingDraft(
      item: {'id': 1},
      location: '1',
      price: '1,250,000',
    );
    expect(draft.validation, isNull);
    expect(draft.amount, 1250000);
    expect(draft.toInput()['price'], 1250000);
    for (final value in ['1,2', ',100', 'NaN', 'Infinity']) {
      draft.price = value;
      expect(draft.amount, isNull);
      expect(draft.validation, isNotNull);
    }
  });

  testWidgets('price step preserves quality and editable bounded quantity', (
    tester,
  ) async {
    final c = MarketplaceListingsController(ListingsFixture());
    final draft = ListingDraft(
      item: {'id': 1, 'name': 'Fixture'},
      quality: '702',
      price: '1,250,000',
    );
    await tester.pumpWidget(
      preview(
        ListingPublishDialog(c, draft, initialStep: 2),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MarketQualityBadge), findsOneWidget);
    final minus = tester.widget<IconButton>(
      find.byKey(const Key('market-publish-qty-dec')),
    );
    expect(minus.onPressed, isNull);
    await tester.tap(find.byKey(const Key('market-publish-qty-inc')));
    await tester.pump();
    expect(draft.quantity, '2');
    await tester.enterText(
      find.byKey(const ValueKey('publish-quantity')),
      '999999',
    );
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('market-publish-qty-inc')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('manifest barter confirmation identifies list and quantity', (
    tester,
  ) async {
    final c = MarketplaceListingsController(ListingsFixture())
      ..manifests = [
        {'id': 9, 'name': 'Fixture manifest'},
      ];
    final draft = ListingDraft(
      manifestId: 9,
      side: 'barter',
      quantity: '5',
      wanted: 'Wanted fixture',
      visible: false,
    );
    await tester.pumpWidget(
      preview(
        ListingPublishDialog(c, draft, initialStep: 3),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fixture manifest'), findsOneWidget);
    expect(find.text('数量'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('—'), findsNothing);
    expect(find.text('发布后先不上架，可在“我的挂单”中上架。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('buy confirmation describes seller response and approval', (
    tester,
  ) async {
    final c = MarketplaceListingsController(ListingsFixture());
    final draft = ListingDraft(
      item: {'id': 1, 'name': 'Fixture'},
      side: 'buy',
      price: '10',
    );
    await tester.pumpWidget(
      preview(
        ListingPublishDialog(c, draft, initialStep: 3),
        AppearanceMode.light,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('发布后会出现在市场里，卖家响应后你会在“待我处理”里确认是否同意。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
