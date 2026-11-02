// The hall head's figures share the room its plate and buttons leave. One that
// does not fit goes whole; it is never cut in half (user report, 1280 window).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_banner.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';

import 'marketplace_slice4_test.dart' show preview;
import 'marketplace_trade_profile_test.dart' show ProfilePort, fixtureProfile;

void main() {
  testWidgets('no figure is ever cut, at any window width', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = MarketplaceController(ProfilePort())
      ..tradeProfile = {
        ...fixtureProfile(),
        // Wide enough to overflow every width below; real figures vary too.
        'point': '9' * 50,
      };
    var hidden = 0, shown = 0;
    for (var width = 1000.0; width <= 1700; width += 20) {
      tester.view.physicalSize = Size(width, 400);
      await tester.pumpWidget(
        preview(
          Align(
            alignment: Alignment.topCenter,
            child: MarketHallHead(
              c,
              search: const SizedBox.shrink(),
              onRefresh: null,
            ),
          ),
          AppearanceMode.dark,
        ),
      );
      await tester.pump();
      final wrap = find.byType(Wrap);
      final box = tester.getRect(wrap);
      for (final text in find
          .descendant(of: wrap, matching: find.byType(RichText))
          .evaluate()) {
        final rect = tester.getRect(find.byWidget(text.widget));
        if (rect.top >= box.bottom) {
          hidden++;
          continue;
        }
        shown++;
        expect(
          rect.right,
          lessThanOrEqualTo(box.right + .01),
          reason: 'A figure is cut at width $width',
        );
      }
      expect(tester.takeException(), isNull);
    }
    expect(shown, greaterThan(0));
    expect(hidden, greaterThan(0), reason: 'The narrow widths must overflow');
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump(const Duration(minutes: 1));
  });
}
