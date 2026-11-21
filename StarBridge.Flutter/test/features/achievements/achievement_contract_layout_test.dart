import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';

import 'achievement_collection_controller_test.dart'
    show achievementTestAccount;

class _Records implements AchievementCollectionPort {
  const _Records(this.swiftEarned);
  final bool swiftEarned;

  @override
  Future<AchievementCollection> read({required int generation}) async =>
      AchievementCollection(
        generation: generation,
        status: AchievementCollectionStatus.ready,
        earnedAt: {
          'first-entry': DateTime.utc(2026, 11, 3),
          if (swiftEarned) 'contract-tsg-swift': DateTime.utc(2026, 11, 3),
        },
      );
}

void main() {
  for (final locale in AppStrings.supportedLocales) {
    for (final swiftEarned in [false, true]) {
      testWidgets('$locale 320 px 1.6x contract layout earned=$swiftEarned', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final account = ValueNotifier(achievementTestAccount(1));
        addTearDown(account.dispose);
        final strings = AppStrings.resolve(locale);
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
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              locale,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.6),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: AchievementsPage(
                account: account,
                port: _Records(swiftEarned),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final first = find.byKey(const Key('achievement-entry-first-entry'));
        await tester.ensureVisible(first);
        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('achievement-detail')), findsOneWidget);
        await tester.tap(find.byKey(const Key('achievement-detail-close')));
        await tester.pumpAndSettle();

        final search = find.byKey(const Key('achievement-search'));
        await tester.ensureVisible(search);
        await tester.enterText(
          search,
          strings.text('achievements.contractTsgSwift.name'),
        );
        await tester.pumpAndSettle();
        final swift = find.byKey(
          const Key('achievement-entry-contract-tsg-swift'),
        );
        // A fully wrapped contract condition can be taller than the viewport.
        // Open it through its visible title, as a reader would.
        final title = find.descendant(
          of: swift,
          matching: find.text(
            strings.text('achievements.contractTsgSwift.name'),
          ),
        );
        await tester.ensureVisible(title);
        await tester.tap(title);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('achievement-detail')), findsOneWidget);
        final detail = find.descendant(
          of: find.byKey(const Key('achievement-detail')),
          matching: find.byType(Text),
        );
        final texts = tester.widgetList<Text>(detail).map((text) => text.data);
        expect(
          texts,
          contains(strings.text('achievements.contractTsgSwift.note')),
        );
        expect(
          texts.whereType<String>().any((text) => text.contains('90')),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
