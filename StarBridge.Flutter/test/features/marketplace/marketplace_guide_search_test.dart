import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_page.dart';
import 'package:starbridge_flutter/shared/guide/guide_controller.dart';
import 'package:starbridge_flutter/shared/guide/guide_scope.dart';
import 'package:starbridge_flutter/shared/guide/guide_state.dart';
import 'package:starbridge_flutter/shared/guide/guide_state_adapters.dart';

import 'marketplace_test.dart' show FixturePort;

void main() {
  testWidgets('"Browse the trading hall" needs a submitted search, not typing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final guide = GuideController(
      InMemoryGuideState(const GuideState(available: true, eligible: true)),
    );
    final online = ValueNotifier(true);
    final hub = GuideHub(
      controller: guide,
      online: online,
      navigate: (_) {},
    );
    final c = MarketplaceController(FixturePort());
    addTearDown(() {
      c.dispose();
      hub.dispose();
      guide.dispose();
      online.dispose();
    });
    const locale = Locale('en', 'US');
    await tester.pumpWidget(
      MaterialApp(
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
        // Tours are not under test here; the scope only carries the hub.
        builder: (_, child) => GuideScope(hub: hub, child: child!),
        home: Scaffold(body: MarketplacePage(c)),
      ),
    );
    await tester.pumpAndSettle();
    // Seen tours stay out of the way of the page.
    guide.markSeen('tour.market');
    await c.focusSearch();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('marketplace-search')),
      'raw SCM query',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(guide.value.done, isNot(contains('market')));

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(guide.value.done, contains('market'));
    await tester.pumpWidget(const SizedBox());
  });
}
