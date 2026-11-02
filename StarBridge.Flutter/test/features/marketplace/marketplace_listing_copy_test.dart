import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_editor.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';

import 'marketplace_slice4_test.dart' show ListingsFixture;

Widget localized(Widget child, Locale locale) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  home: Scaffold(body: child),
);

void main() {
  for (final (locale, heading, publish, live, edit, save) in [
    (const Locale('zh', 'TW'), '我的掛單', '發布掛單', '上架中', '編輯掛單', '儲存'),
    (
      const Locale('en'),
      'My listings',
      'New listing',
      'Live',
      'Edit listing',
      'Save',
    ),
  ]) {
    testWidgets('listings page and editor follow ${locale.toLanguageTag()}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MarketplaceListingsController(ListingsFixture());
      await tester.pumpWidget(localized(MarketplaceListingsPage(c), locale));
      await tester.pumpAndSettle();
      expect(find.text(heading), findsOneWidget);
      expect(find.text(publish), findsOneWidget);
      expect(find.text(live), findsWidgets);
      final ctx = tester.element(find.byType(MarketplaceListingsPage));
      editListing(ctx, c, c.rows.first);
      await tester.pumpAndSettle();
      expect(find.text(edit), findsOneWidget);
      expect(find.text(save), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
