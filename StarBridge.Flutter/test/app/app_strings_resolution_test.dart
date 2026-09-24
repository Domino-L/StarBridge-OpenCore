import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/app_strings_en.dart';
import 'package:starbridge_flutter/app/localization/app_strings_zh_cn.dart';
import 'package:starbridge_flutter/app/localization/app_strings_zh_tw.dart';

void main() {
  for (final scenario in [
    (const Locale('zh', 'CN'), simplifiedAppStrings),
    (const Locale('zh', 'TW'), traditionalAppStrings),
    (
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      traditionalAppStrings,
    ),
    (const Locale('en', 'US'), englishAppStrings),
    (const Locale('en', 'GB'), englishAppStrings),
    (const Locale('fr', 'FR'), simplifiedAppStrings),
  ]) {
    test('complete catalog resolution for ${scenario.$1}', () {
      final strings = AppStrings.resolve(scenario.$1);
      expect(strings.locale, scenario.$1);
      for (final entry in scenario.$2.entries) {
        expect(strings.text(entry.key), entry.value, reason: entry.key);
      }
      expect(strings.text('missing.test.key'), 'missing.test.key');
    });
  }
  for (final locale in AppStrings.probeLocales) {
    test('pseudo locale $locale transforms every English entry', () {
      final strings = AppStrings.resolve(locale);
      for (final entry in englishAppStrings.entries) {
        expect(strings.text(entry.key), '⟦ ${entry.value} · ${entry.value} ⟧');
      }
    });
  }
  test('production language list remains the accepted three locales', () {
    expect(AppStrings.supportedLocales, const [
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
      Locale('en', 'US'),
    ]);
    expect(
      AppStrings.resolve(const Locale('zh', 'CN')).text('app.name'),
      '星海舰桥',
    );
  });
}
