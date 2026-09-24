import 'package:flutter/widgets.dart';

/// Localized presentation only: the source title remains the scan fact.
abstract final class ShipDisplayNames {
  static String primary(
    Locale locale, {
    required String original,
    String? simplifiedChinese,
    String? traditionalChinese,
  }) {
    if (locale.languageCode != 'zh') return original;
    final traditional =
        locale.scriptCode == 'Hant' ||
        const {'TW', 'HK', 'MO'}.contains(locale.countryCode);
    if (traditional && traditionalChinese?.trim().isNotEmpty == true) {
      return traditionalChinese!.trim();
    }
    return simplifiedChinese?.trim().isNotEmpty == true
        ? simplifiedChinese!.trim()
        : original;
  }
}
