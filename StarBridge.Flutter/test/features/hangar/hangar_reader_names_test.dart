import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_results.dart';
import 'package:starbridge_flutter/features/ships/ship_display_names.dart';
import 'package:starbridge_flutter/shared/ships/catalog_vehicle_icon.dart';

void main() {
  test(
    'Chinese variants use supplied names and unknowns preserve the original',
    () {
      String name(Locale locale, {String? simplified, String? traditional}) =>
          ShipDisplayNames.primary(
            locale,
            original: 'Original Ship',
            simplifiedChinese: simplified,
            traditionalChinese: traditional,
          );
      expect(name(const Locale('zh', 'CN'), simplified: '测试舰'), '测试舰');
      expect(
        name(const Locale('zh', 'TW'), simplified: '测试舰', traditional: '測試艦'),
        '測試艦',
      );
      expect(
        name(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          simplified: '测试舰',
          traditional: '測試艦',
        ),
        '測試艦',
      );
      expect(name(const Locale('zh', 'HK'), simplified: '测试舰'), '测试舰');
      expect(name(const Locale('zh', 'CN'), simplified: ' '), 'Original Ship');
      expect(name(const Locale('en'), simplified: '测试舰'), 'Original Ship');
    },
  );

  for (final complete in [false, true]) {
    testWidgets(
      'live=$complete ship names follow locale without replacing results',
      (tester) async {
        const view = {
          'shipCount': 2,
          'ships': [
            {
              'title': 'Vulture',
              'liner': 'Drake',
              'names': {'zhHans': '秃鹫', 'zhHant': '禿鷲'},
              'display': {
                'category': 'industrial',
                'sizeClass': 'small',
                'domain': 'spacecraft',
                'iconKey': 'industrial-small',
              },
            },
            {'title': 'Unknown Variant', 'liner': 'Original Builder'},
          ],
        };
        Future<void> show(Locale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              supportedLocales: const [
                Locale('zh', 'CN'),
                Locale('zh', 'TW'),
                Locale('en'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: buildStarBridgeTheme(
                FutureRestraintStyle.resolve(AppearanceMode.dark),
                locale,
              ),
              home: Scaffold(
                body: SizedBox(
                  width: 320,
                  child: HangarReaderResults(view: view, complete: complete),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<HangarReaderResults>(find.byType(HangarReaderResults))
                .view,
            same(view),
          );
          expect(find.text('Unknown Variant'), findsOneWidget);
          expect(
            find.byType(CatalogVehicleIcon),
            findsOneWidget,
            reason: 'Reader must use the same reviewed presentation as the saved hangar',
          );
          expect(tester.takeException(), isNull);
        }

        await show(const Locale('zh', 'CN'));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('hangar-reader-ship-name-0')))
              .data,
          '秃鹫',
        );
        expect(find.text('Vulture · Drake'), findsOneWidget);
        await show(const Locale('en'));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('hangar-reader-ship-name-0')))
              .data,
          'Vulture',
        );
        expect(find.text('秃鹫'), findsNothing);
        await show(const Locale('zh', 'TW'));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('hangar-reader-ship-name-0')))
              .data,
          '禿鷲',
        );
      },
    );
  }
}
