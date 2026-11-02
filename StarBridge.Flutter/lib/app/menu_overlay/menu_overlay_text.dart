import '../localization/app_strings.dart';
import 'menu_overlay_locale.dart';

/// Only explicit application copy is resolved. User strings are never inspected.
final class MenuOverlayText {
  const MenuOverlayText(this.key, [this.arguments = const {}]);
  final String key;
  final Map<String, Object?> arguments;

  String resolve(AppStrings strings) => menuOverlayFormat(strings, key, {
    for (final entry in arguments.entries)
      entry.key: resolveMenuOverlayValue(entry.value, strings),
  });
}

Object? resolveMenuOverlayValue(Object? value, AppStrings strings) {
  if (value is MenuOverlayText) return value.resolve(strings);
  if (value is MenuOverlayJoin) {
    return value.values
        .map((item) => resolveMenuOverlayValue(item, strings))
        .where((item) => item != null && item != '')
        .join(value.separator);
  }
  if (value is MenuOverlayComputed) return value.read(strings);
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: resolveMenuOverlayValue(entry.value, strings),
    };
  }
  if (value is List) {
    return [for (final item in value) resolveMenuOverlayValue(item, strings)];
  }
  return value;
}

final class MenuOverlayJoin {
  const MenuOverlayJoin(this.values, [this.separator = '']);
  final List<Object?> values;
  final String separator;
}

final class MenuOverlayComputed {
  const MenuOverlayComputed(this.read);
  final String Function(AppStrings) read;
}
