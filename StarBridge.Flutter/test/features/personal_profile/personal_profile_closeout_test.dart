import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_favorite_ships.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_hangar_overview.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_role_catalog.dart';

void main() {
  testWidgets(
    'unavailable hangar shows an explanation instead of a zero count',
    (tester) async {
      await _pump(
        tester,
        const PersonalProfileHangarOverview(
          summary: PersonalProfileHangarSummary.empty(),
          span: 1,
        ),
      );
      expect(
        find.byKey(const Key('profile-hangar-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('profile-hangar-count-panel')), findsNothing);
      expect(find.textContaining('机库资料待接入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unresolved favorites retain their count and show a useful empty state',
    (tester) async {
      await _pump(
        tester,
        const PersonalProfileFavoriteShips(
          ships: [],
          span: 1,
          hangarAvailable: false,
          unresolvedCount: 3,
        ),
      );
      expect(find.textContaining('已保留 3 艘最爱舰船'), findsOneWidget);
      expect(
        find.byKey(const Key('profile-favorites-empty-state')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an available hangar with no favorites gets a distinct empty state',
    (tester) async {
      await _pump(
        tester,
        const PersonalProfileFavoriteShips(ships: [], span: 1),
      );
      expect(find.text('还没有设置最爱舰船。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'all old role IDs have translated labels and original semantic categories',
    () {
      expect(PersonalProfileRoleCatalog.categories.length, 35);
      for (final locale in AppStrings.supportedLocales) {
        final strings = AppStrings.resolve(locale);
        for (final entry in PersonalProfileRoleCatalog.categories.entries) {
          final tag = PersonalProfileRoleCatalog.resolve(entry.key)!;
          expect(tag.category, entry.value);
          expect(tag.displayLabel, isNull);
          expect(strings.text(tag.labelKey), isNot(tag.labelKey));
          expect(strings.text(tag.labelKey), isNot(entry.key));
        }
      }
      final strings = AppStrings.resolve(const Locale('zh', 'CN'));
      expect(
        strings.text(
          PersonalProfileRoleCatalog.resolve('fleet-command')!.labelKey,
        ),
        '舰队指挥',
      );
      expect(
        strings.text(
          PersonalProfileRoleCatalog.resolve('assault-trooper')!.labelKey,
        ),
        '突击队员',
      );
      expect(PersonalProfileRoleCatalog.resolve('玩家自定义岗位'), isNull);
    },
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('zh', 'CN'),
      ),
      home: Scaffold(body: SizedBox(width: 330, height: 190, child: child)),
    ),
  );
  await tester.pumpAndSettle();
}
