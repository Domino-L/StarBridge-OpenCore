import 'dart:ui';

import '../ships/ship_display_names.dart';
import 'local_hangar_port.dart';

abstract final class LocalHangarNames {
  static String model(Locale locale, LocalHangarShip ship) =>
      ShipDisplayNames.primary(
        locale,
        original: ship.title,
        simplifiedChinese: ship.cn,
        traditionalChinese: ship.tw,
      );
  static String primary(Locale locale, LocalHangarShip ship) =>
      ship.nickname?.trim().isNotEmpty == true
      ? ship.nickname!.trim()
      : model(locale, ship);
  static bool matches(LocalHangarShip ship, String query) => [
    ship.nickname,
    ship.notes,
    ship.title,
    ship.cn,
    ship.tw,
    ship.liner,
  ].whereType<String>().any((value) => value.toLowerCase().contains(query));
}
