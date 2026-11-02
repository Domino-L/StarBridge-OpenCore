import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/achievements/achievements_feature.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  testWidgets('avatar menu opens the achievement route and can leave it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final composition = AppComposition.forShellReview(
      windowChrome: InMemoryWindowChrome(),
    );
    await tester.pumpWidget(StarBridgeApp(composition: composition));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('account-menu-achievements'));
    expect(entry, findsOneWidget);
    expect(
      find.byKey(const Key('account-menu-personal-profile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('account-menu-account-and-identity')),
      findsOneWidget,
    );
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('achievements-page')), findsOneWidget);
    expect(find.byType(AchievementsPage), findsOneWidget);
    expect(find.byKey(const Key('account-menu-achievements')), findsNothing);
    final destinationContext = tester.element(find.byType(AchievementsPage));
    expect(
      AppStrings.of(destinationContext).text('navigation.achievements'),
      '成就中心',
    );
    expect(
      composition.features.byRoute('/achievements').navigationRegion,
      NavigationRegion.accountMenu,
    );
    expect(
      composition.features.byRoute('/achievements').availability,
      FeatureAvailability.available,
    );
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('achievements-page')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (locale, title) in [
    (const Locale('zh', 'CN'), '成就中心'),
    (const Locale('zh', 'TW'), '成就中心'),
    (const Locale('en'), 'Achievements'),
  ]) {
    for (final mode in [AppearanceMode.light, AppearanceMode.dark]) {
      testWidgets('achievement destination fits $locale $mode at 320 px', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final account = createAccountModule(InMemoryAccountAdapter());
        addTearDown(account.dispose);
        await account.initialize();
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStringsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(mode),
              locale,
            ),
            home: Scaffold(
              body: Builder(
                builder: createAchievementsFeature(account).buildDestination,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(AchievementsPage));
        expect(AppStrings.of(context).text('navigation.achievements'), title);
        expect(find.textContaining(title), findsWidgets);
        final entry = find.byKey(const Key('achievement-entry-first-entry'));
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('achievement-detail')), findsOneWidget);
        await tester.tap(find.byKey(const Key('achievement-detail-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('achievement-detail')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
