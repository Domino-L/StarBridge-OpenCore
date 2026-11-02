// Slice32: the publish wizard's price step plus its header and footer —
// close, back / cancel / next, quantity steppers, the wanted-item and location
// selects, expiry segments, "edit trade profile" and "list right away".
// Native geometry measured before the change is pinned for the standard
// suite; every suite keeps one reader action per control, pointer activation
// and the draft values the wizard publishes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';

import 'marketplace_slice4_test.dart' show ListingsFixture;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import 'marketplace_trade_action_fields_motion_test.dart' show namedOrChecked;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

Finder _k(String key) => find.byKey(Key(key));

Future<(MarketplaceListingsController, ListingDraft)> _controller(
  String side, {
  String location = '1',
  String price = '',
}) async {
  final c = MarketplaceListingsController(ListingsFixture());
  await c.refresh();
  final draft = ListingDraft(
    item: {'id': c.items.first['id'], 'name': c.items.first['name']},
    side: side,
    location: location,
    price: price,
  );
  return (c, draft);
}

void main() {
  for (final side in ['sell', 'barter']) {
    testWidgets('standard suite keeps the measured native geometry ($side)', (
      tester,
    ) async {
      size(tester, const Size(1280, 900));
      final (c, draft) = await _controller(side);
      var profiles = 0;
      try {
        await tester.pumpWidget(
          scopedApp(
            ListingPublishDialog(
              c,
              draft,
              initialStep: 2,
              editProfile: () async => profiles++,
            ),
            InteractionSuite.standard,
          ),
        );
        await tester.pumpAndSettle();
        // Re-measured 2026-10-20 after the user-requested price-step restyle
        // (6px field radius, centred quantity with borderless 40px steppers);
        // Barter's wanted-item select makes its dialog 1px taller, so rows
        // above the location row sit 0.5px higher and rows below 0.5px lower.
        final barter = side == 'barter';
        final up = barter ? -.5 : 0.0, down = barter ? .5 : 0.0;
        Rect above(double l, double t, double r, double b) =>
            Rect.fromLTRB(l, t + up, r, b + up);
        Rect at(double l, double t, double r, double b) =>
            Rect.fromLTRB(l, t + down, r, b + down);
        expect(
          tester.getRect(_k('market-publish-close')),
          above(852, 185, 900, 233),
        );
        expect(
          tester.getRect(_k('market-publish-qty-dec')),
          above(750, 416.5, 790, 456.5),
        );
        expect(
          tester.getRect(_k('market-publish-qty-inc')),
          above(860, 416.5, 900, 456.5),
        );
        if (side == 'barter') {
          expect(
            tester.getRect(
              find.byType(StarBridgeSelectFormField<String>).first,
            ),
            const Rect.fromLTRB(380, 414.5, 738, 458.5),
          );
        }
        expect(
          tester.getRect(find.byType(StarBridgeSelectFormField<String>).last),
          within(distance: .001, from: at(380, 493, 670.8, 537)),
        );
        expect(
          tester.getRect(_k('market-publish-days')),
          within(distance: .001, from: at(682.8, 493, 900, 533)),
        );
        expect(
          tester.getRect(_k('market-publish-profile')),
          at(656.5, 549, 748.5, 597),
        );
        expect(
          tester.getRect(_k('market-publish-visible')),
          at(380, 605, 420, 645),
        );
        expect(
          tester.getRect(_k('market-publish-back')),
          at(380, 665, 436, 713),
        );
        expect(
          tester.getRect(_k('market-publish-cancel')),
          at(732, 665, 804, 713),
        );
        expect(
          tester.getRect(_k('market-publish-next')),
          at(812, 665, 900, 713),
        );
        await tester.tap(_k('market-publish-profile'));
        expect(profiles, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    });
  }

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: price step controls by reader and pointer, then next/back',
      (tester) async {
        size(tester, const Size(1280, 900));
        final semantics = tester.ensureSemantics();
        final (c, draft) = await _controller(
          'sell',
          location: '',
          price: '1000',
        );
        try {
          await tester.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        ListingPublishDialog(c, draft, initialStep: 2),
                  ),
                  child: const Text('open'),
                ),
              ),
              suite,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          activate(tester, namedButton(tester, '增加数量'));
          await tester.pumpAndSettle();
          await tester.tap(_k('market-publish-qty-inc'));
          await tester.pumpAndSettle();
          activate(tester, namedButton(tester, '减少数量'));
          await tester.pumpAndSettle();
          expect(draft.quantity, '2');
          activate(tester, namedButton(tester, '永久'));
          await tester.pumpAndSettle();
          expect(draft.days, 0);
          await tester.tap(find.text('发布后立即上架'), warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(draft.visible, isFalse);
          activate(tester, namedOrChecked(tester, '发布后立即上架'));
          await tester.pumpAndSettle();
          expect(draft.visible, isTrue);
          await tester.tap(_k('market-publish-location'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('新巴贝奇').last);
          await tester.pumpAndSettle();
          expect(draft.location, '1');
          activate(tester, namedButton(tester, '下一步'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('publish-step-3')), findsOneWidget);
          activate(tester, namedButton(tester, '上一步'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('publish-step-2')), findsOneWidget);
          activate(tester, namedButton(tester, '关闭'));
          await tester.pumpAndSettle();
          expect(find.byType(ListingPublishDialog), findsNothing);
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          await tester.tap(_k('market-publish-cancel'));
          await tester.pumpAndSettle();
          expect(find.byType(ListingPublishDialog), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );
  }
}
