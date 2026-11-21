// Plan item 9: the SCM-only prompts name the account card the user will find.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/localization/account_card_title.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/account/account_safety_dialog.dart';

const _prompts = [
  'gameplay.accountScmOnly',
  'settings.privacy.recentlyPlayed.scmOnly',
  'settings.privacy.events.scmOnly',
];

Widget _app(
  FeatureRegistry registry, {
  Locale locale = const Locale('zh', 'CN'),
  required WidgetBuilder home,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => registry.appScope(child!),
  home: Builder(builder: home),
);

FeatureRegistry _registry(ValueListenable<bool> offered) => FeatureRegistry([
  FeatureDescriptor(
    id: 'home',
    route: '/',
    labelKey: 'home.label',
    descriptionKey: 'home.description',
    icon: StarBridgeIconSemantic.home,
    navigationRegion: NavigationRegion.brand,
    order: 0,
    buildDestination: (_) => const SizedBox.shrink(),
    appScopeBuilder: (child) =>
        AccountCardTitle(migrationOffered: offered, child: child),
  ),
]);

void main() {
  test(
    'every SCM-only prompt carries the card placeholder in each language',
    () {
      for (final locale in AppStrings.supportedLocales) {
        final strings = AppStrings.resolve(locale);
        for (final key in _prompts) {
          expect(strings.text(key), contains('{accountCard}'), reason: key);
          expect(strings.text(key), isNot(contains('旧数据兼容')));
        }
      }
    },
  );

  for (final (locale, off, on) in const [
    (Locale('zh', 'CN'), '› 旧数据兼容。', '› 迁移旧账号。'),
    (Locale('zh', 'TW'), '› 舊資料相容。', '› 遷移舊帳號。'),
    (
      Locale('en', 'US'),
      '› Legacy data compatibility.',
      '› Migrate old account.',
    ),
  ]) {
    testWidgets('prompts follow the card title in a dialog: $locale', (
      tester,
    ) async {
      final offered = ValueNotifier(false);
      final seen = <String>[];
      late BuildContext page;
      await tester.pumpWidget(
        _app(
          _registry(offered),
          locale: locale,
          home: (context) {
            page = context;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();
      // A dialog route sits under the navigator, outside the page tree.
      showDialog<void>(
        context: page,
        builder: (context) {
          final strings = AppStrings.of(context);
          seen
            ..clear()
            ..add(accountSafetyText(context, 'scmOnly'))
            ..addAll(
              _prompts.map(
                (key) => withAccountCardTitle(context, strings.text(key)),
              ),
            );
          return const SizedBox.shrink();
        },
      );
      await tester.pumpAndSettle();
      expect(seen, hasLength(4));
      for (final text in seen) {
        expect(text, endsWith(off));
      }
      offered.value = true;
      await tester.pumpAndSettle();
      for (final text in seen) {
        expect(text, endsWith(on));
      }
      await tester.pumpWidget(const SizedBox());
      offered.dispose();
    });
  }

  testWidgets('without the scope the card is the compatibility card', (
    tester,
  ) async {
    late String text;
    await tester.pumpWidget(
      _app(
        FeatureRegistry([
          FeatureDescriptor(
            id: 'home',
            route: '/',
            labelKey: 'home.label',
            descriptionKey: 'home.description',
            icon: StarBridgeIconSemantic.home,
            navigationRegion: NavigationRegion.brand,
            order: 0,
            buildDestination: (_) => const SizedBox.shrink(),
          ),
        ]),
        home: (context) {
          text = accountSafetyText(context, 'scmOnly');
          return const SizedBox.shrink();
        },
      ),
    );
    await tester.pump();
    expect(text, endsWith('› 旧数据兼容。'));
  });
}
