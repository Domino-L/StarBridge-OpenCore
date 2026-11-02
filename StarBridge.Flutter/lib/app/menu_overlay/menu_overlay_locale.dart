import 'package:flutter/widgets.dart';

import '../localization/app_strings.dart';

Locale menuOverlayLocale(String? language) => switch (language) {
  'en' || 'en-US' => const Locale('en', 'US'),
  'zh-TW' => const Locale('zh', 'TW'),
  _ => const Locale('zh', 'CN'),
};

String menuText(
  BuildContext? context,
  String key, [
  Map<String, Object?> arguments = const {},
]) {
  final strings =
      (context == null
          ? null
          : Localizations.of<AppStrings>(context, AppStrings)) ??
      AppStrings.resolve(const Locale('zh', 'CN'));
  return menuOverlayFormat(strings, key, arguments);
}

String menuOverlayFormat(
  AppStrings strings,
  String key, [
  Map<String, Object?> arguments = const {},
]) {
  final template = strings.text(key);
  return template.replaceAllMapped(
    RegExp(r'\{([^{}]+)\}'),
    (match) => arguments.containsKey(match[1])
        ? '${arguments[match[1]] ?? ''}'
        : match[0]!,
  );
}

String? menuOverlayRecord(Locale locale, (String, String, String)? copy) =>
    copy == null
    ? null
    : locale.languageCode != 'zh'
    ? copy.$3
    : locale.countryCode == 'TW'
    ? copy.$2
    : copy.$1;
