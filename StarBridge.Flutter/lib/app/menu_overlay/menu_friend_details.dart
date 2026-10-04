import '../localization/app_strings.dart';

/// Bounded display data. No opaque account references or arbitrary shared fields.
class MenuFriendDetails {
  const MenuFriendDetails(this.values, this.labels);
  static const fields = ['serverId', 'serverRegion', 'ship', 'location'];
  final Map<String, String> values;
  final Map<String, Map<String, String>> labels;

  static MenuFriendDetails? parse(Object? raw, Object? names) {
    if (raw == null) return null;
    if (raw is! Map || raw.keys.any((key) => !fields.contains(key))) {
      throw const FormatException();
    }
    String checked(Object? value) {
      if (value is! String || value.length > 512 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
        throw const FormatException();
      }
      return value;
    }
    final values = {for (final entry in raw.entries) entry.key as String: checked(entry.value)};
    final labels = <String, Map<String, String>>{};
    if (names != null) {
      if (names is! Map || names.keys.any((key) => !const ['ship', 'location'].contains(key))) {
        throw const FormatException();
      }
      for (final entry in names.entries) {
        final locales = entry.value;
        if (locales is! Map || locales.keys.any((key) => !const ['en', 'zhHans', 'zhHant'].contains(key))) {
          throw const FormatException();
        }
        if (values.containsKey(entry.key)) {
          labels[entry.key as String] = {
            for (final name in locales.entries) name.key as String: checked(name.value),
          };
        }
      }
    }
    return MenuFriendDetails(Map.unmodifiable(values), Map.unmodifiable(labels));
  }

  List<String> localized(AppStrings strings) => [
    for (final key in fields)
      if (values[key]?.isNotEmpty == true) _localizedValue(key, strings),
  ];

  String _localizedValue(String key, AppStrings strings) {
    final original = values[key]!;
    if (key == 'serverRegion' && const ['US', 'EU', 'AU', 'ASIA'].contains(original.toUpperCase())) {
      return strings.text('gameLog.region${original.toUpperCase()}');
    }
    final names = labels[key] ?? const {};
    final locale = strings.locale;
    final traditional = locale.countryCode == 'TW' || locale.countryCode == 'HK' || locale.scriptCode == 'Hant';
    return locale.languageCode == 'zh'
        ? names[traditional ? 'zhHant' : 'zhHans'] ?? names['zhHans'] ?? names['en'] ?? original
        : names['en'] ?? original;
  }
}
