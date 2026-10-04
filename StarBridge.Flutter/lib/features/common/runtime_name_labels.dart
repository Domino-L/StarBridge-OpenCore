import 'dart:ui' show Locale;

/// Optional Host presentation data; malformed enrichment cannot break the
/// authoritative member or replace an absent/withheld runtime field.
Map<String, String> parseRuntimeNameLabels(Object? value) {
  if (value is! Map) return const {};
  return Map.unmodifiable({
    for (final key in const ['en', 'zhHans', 'zhHant'])
      if (value[key] is String &&
          (value[key] as String).length <= 512 &&
          (value[key] as String).trim().isNotEmpty)
        key: (value[key] as String).trim(),
  });
}

String runtimeNameLabel(
  String original,
  Map<String, String> labels,
  Locale locale,
) {
  if (locale.languageCode != 'zh') return labels['en'] ?? original;
  final traditional =
      locale.scriptCode == 'Hant' ||
      locale.countryCode == 'TW' ||
      locale.countryCode == 'HK';
  return labels[traditional ? 'zhHant' : 'zhHans'] ??
      labels['zhHans'] ??
      labels['en'] ??
      original;
}
