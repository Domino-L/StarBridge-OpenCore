import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';

import 'marketplace_test.dart' show FixturePort, app;

// Regression (user report 2026-10-20): every visit from another page opened
// the trading hall's search. Only the search shortcut may focus it, once.
void main() {
  bool searchFocused(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('marketplace-search')))
      .focusNode!
      .hasFocus;

  testWidgets('a shortcut focuses search once; later visits do not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = MarketplaceController(FixturePort());
    addTearDown(c.dispose);

    // An ordinary visit: nothing is focused.
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    expect(searchFocused(tester), isFalse);

    // Ctrl+K lands in the search box.
    await c.focusSearch();
    await tester.pumpAndSettle();
    expect(searchFocused(tester), isTrue);

    // Leave and come back (the page is built again): the old request is spent.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    expect(searchFocused(tester), isFalse);

    // A shortcut pressed from another page focuses the newly built page once.
    await tester.pumpWidget(const SizedBox.shrink());
    await c.focusSearch();
    await tester.pumpWidget(app(c, AppearanceMode.dark, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    expect(searchFocused(tester), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
