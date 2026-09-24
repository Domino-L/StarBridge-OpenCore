import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_strings_zh_cn.dart';
import 'app_strings_zh_tw.dart';
import 'app_strings_en.dart';

final class AppStrings {
  const AppStrings._(this.locale, this._values);

  final Locale locale;
  final Map<String, String> _values;

  static const supportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en', 'US'),
  ];

  static const probeLocales = <Locale>[Locale('en', 'XA'), Locale('ar', 'XB')];

  static List<Locale> runtimeSupportedLocales() => [
    ...supportedLocales,
    if (!kReleaseMode) ...probeLocales,
  ];

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings)!;
  }

  String text(String key) => _values[key] ?? key;

  static AppStrings resolve(Locale locale) {
    if (locale.countryCode == 'XA') {
      return AppStrings._(locale, _pseudo(englishAppStrings));
    }
    if (locale.countryCode == 'XB') {
      return AppStrings._(locale, _pseudo(englishAppStrings));
    }
    if (locale.languageCode == 'en') {
      return AppStrings._(locale, englishAppStrings);
    }
    if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') {
      return AppStrings._(locale, traditionalAppStrings);
    }
    return AppStrings._(locale, simplifiedAppStrings);
  }

  static Map<String, String> _pseudo(Map<String, String> source) {
    return source.map((key, value) => MapEntry(key, '⟦ $value · $value ⟧'));
  }
}

final class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppStrings.supportedLocales.any(
        (item) => item.languageCode == locale.languageCode,
      ) ||
      AppStrings.probeLocales.any(
        (item) =>
            item.languageCode == locale.languageCode &&
            item.countryCode == locale.countryCode,
      );

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings.resolve(locale);

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}
