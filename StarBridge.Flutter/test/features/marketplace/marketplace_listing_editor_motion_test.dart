// Slice31: the listing editor dialog — close, quantity steppers, expiry
// segments, the "listed" checkbox row, delete (with its confirmation),
// cancel and save. Native geometry and text style measured before the change
// are pinned for the standard suite; every suite keeps one reader action per
// control, pointer activation, keyboard focus and the written values.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_slice4_test.dart' show ListingsFixture;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import 'marketplace_trade_action_fields_motion_test.dart' show namedOrChecked;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

const _a = '科力晶（单个矿块）';

class _CapturePort extends ListingsFixture {
  final inputs = <MarketRow>[];
  @override
  Future<void> write(String op, MarketRow input) {
    inputs.add({'op': op, ...input});
    return super.write(op, input);
  }
}

Finder _k(String key) => find.byKey(Key(key));

Future<(MarketplaceListingsController, _CapturePort)> _editor(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 900));
  final port = _CapturePort();
  final c = MarketplaceListingsController(port);
  await tester.pumpWidget(scopedApp(MarketplaceListingsPage(c), suite));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<(String, Object?)>(('market-listing-edit', _a))),
  );
  await tester.pumpAndSettle();
  return (c, port);
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    final (c, _) = await _editor(tester, InteractionSuite.standard);
    try {
      expect(
        tester.getRect(_k('market-listing-edit-close')),
        const Rect.fromLTRB(802, 241, 850, 289),
      );
      expect(
        tester.getRect(_k('market-listing-qty-dec')),
        const Rect.fromLTRB(717, 396, 757, 436),
      );
      expect(
        tester.getRect(_k('market-listing-qty-inc')),
        const Rect.fromLTRB(809, 396, 849, 436),
      );
      expect(
        tester.getRect(_k('market-listing-days')),
        within(distance: .001, from: const Rect.fromLTRB(430, 501, 647.2, 541)),
      );
      expect(
        tester.getRect(_k('market-listing-visible')),
        const Rect.fromLTRB(430, 551, 470, 591),
      );
      final listed = find.text('上架');
      expect(tester.getRect(listed), const Rect.fromLTRB(470, 561, 498.5, 581));
      final style = tester
          .widget<RichText>(
            find.descendant(of: listed, matching: find.byType(RichText)),
          )
          .text
          .style!;
      expect(style.fontSize, 14);
      expect(style.color?.toARGB32(), 0xffe7eef2);
      expect(
        tester.getRect(_k('market-listing-delete')),
        const Rect.fromLTRB(430, 609, 498, 657),
      );
      expect(
        tester.getRect(_k('market-listing-edit-cancel')),
        const Rect.fromLTRB(682, 609, 754, 657),
      );
      expect(
        tester.getRect(_k('market-listing-save')),
        const Rect.fromLTRB(762, 609, 850, 657),
      );
      await tester.tap(_k('market-listing-delete'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_k('market-listing-delete-cancel')),
        const Rect.fromLTRB(612, 467.5, 660, 515.5),
      );
      expect(
        tester.getRect(_k('market-listing-delete-confirm')),
        const Rect.fromLTRB(668, 467.5, 756, 515.5),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: steppers, expiry and listed write by reader and pointer',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (c, port) = await _editor(tester, suite);
        try {
          activate(tester, namedButton(tester, '增加'));
          await tester.pumpAndSettle();
          await tester.tap(_k('market-listing-qty-inc'));
          await tester.pumpAndSettle();
          activate(tester, namedButton(tester, '减少'));
          await tester.pumpAndSettle();
          activate(tester, namedButton(tester, '永久'));
          await tester.pumpAndSettle();
          // The whole row toggles, like the native InkWell row.
          await tester.tap(find.text('上架'), warnIfMissed: false);
          await tester.pumpAndSettle();
          activate(tester, namedOrChecked(tester, '上架'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('上架'), warnIfMissed: false);
          await tester.pumpAndSettle();
          activate(tester, namedButton(tester, '保存'));
          await tester.pumpAndSettle();
          final update = port.inputs.single;
          expect(update['op'], 'update');
          expect(update['quantity'], 6);
          expect(update['expiryDays'], 0);
          expect(update['visible'], false);
          expect(_k('market-listing-save'), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets('${suite.name}: delete confirmation, cancel and close', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (c, port) = await _editor(tester, suite);
      try {
        activate(tester, namedButton(tester, '删除挂单'));
        await tester.pumpAndSettle();
        // "Cancel" is autofocused in the confirmation.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(_k('market-listing-delete-confirm'), findsNothing);
        expect(port.inputs, isEmpty);
        activate(tester, namedButton(tester, '取消'));
        await tester.pumpAndSettle();
        expect(_k('market-listing-save'), findsNothing);
        await tester.tap(
          find.byKey(
            const ValueKey<(String, Object?)>(('market-listing-edit', _a)),
          ),
        );
        await tester.pumpAndSettle();
        activate(tester, namedButton(tester, '关闭'));
        await tester.pumpAndSettle();
        expect(_k('market-listing-save'), findsNothing);
        await tester.tap(
          find.byKey(
            const ValueKey<(String, Object?)>(('market-listing-edit', _a)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(_k('market-listing-delete'));
        await tester.pumpAndSettle();
        await tester.tap(_k('market-listing-delete-confirm'));
        await tester.pumpAndSettle();
        expect(port.inputs.single['op'], 'delete');
        expect(_k('market-listing-save'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });
  }
}
