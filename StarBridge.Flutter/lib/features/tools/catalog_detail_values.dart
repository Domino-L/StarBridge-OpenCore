import '../../app/localization/app_strings.dart';
import 'catalog_port.dart';

String catalogOptionalName(
  CatalogRow row,
  String locale,
  String field, [
  String? cn,
]) {
  final value = catalogName(row, locale, field, cn);
  return value == '—' ? '' : value;
}

String catalogStanding(Object? value, AppStrings strings) {
  final row = catalogObject(value), locale = strings.locale.languageCode;
  final scope = catalogOptionalName(row, locale, 'scopeDisplayName');
  final name = catalogOptionalName(row, locale, 'name', 'rankNameCn');
  return [
        if (scope.isNotEmpty)
          scope
        else if (row['scopeName'] is String)
          row['scopeName'],
        if (name.isNotEmpty)
          name
        else if (row['rankIndex'] is num)
          '${strings.text('catalog.rank')} ${row['rankIndex']}',
        if (row['minReputation'] is num) '${row['minReputation']}',
      ]
      .where((part) => part != null && part.toString().trim().isNotEmpty)
      .join(' · ');
}

String catalogDifficulty(Object? value, String locale) {
  final row = catalogObject(value);
  return [
    catalogOptionalName(row, locale, 'name'),
    if (row['level'] is num) '${row['level']}',
    if (row['value'] is num) '${row['value']}',
  ].where((part) => part.isNotEmpty).join(' · ');
}

List<String> catalogEncounterNames(Object? value, String locale) {
  final names = <String>{};
  void ships(CatalogRow row) {
    for (final ship in catalogRows(row['possibleShips'])) {
      final label = catalogOptionalName(ship, locale, 'nameEn');
      final fallback = catalogOptionalName(ship, locale, 'name');
      final name = locale == 'en'
          ? (label.isEmpty ? fallback : label)
          : (fallback.isEmpty ? label : fallback);
      if (name.isNotEmpty) names.add(name);
    }
  }

  final row = catalogObject(value);
  ships(row);
  for (final group in catalogRows(row['spawnGroups'])) {
    ships(group);
    for (final wave in catalogRows(group['waves'])) {
      for (final slot in catalogRows(wave['slots'])) {
        ships(slot);
      }
    }
  }
  return names.toList();
}

List<String> catalogRewardNames(Object? value, String locale) {
  final names = <String>[];
  void visit(Object? value, int depth) {
    if (depth > 4) return;
    for (final row in catalogRows(value)) {
      final name = catalogOptionalName(row, locale, 'name', 'nameCn');
      final fallback = catalogOptionalName(row, locale, 'nameEn', 'nameCn');
      final label = locale == 'en'
          ? (fallback.isEmpty ? name : fallback)
          : (name.isEmpty ? fallback : name);
      if (label.isNotEmpty) {
        final count = row['amount'];
        names.add(
          '$label${count == null || count.toString().trim().isEmpty ? '' : ' ×$count'}',
        );
      }
      for (final group in catalogRows(row['groups'])) {
        visit(group['items'], depth + 1);
      }
    }
  }

  visit(value, 0);
  return names;
}

// Common display stats selected from ScMarketVue blueprint/types.ts configs.
const catalogBaseStatUnits = <String, String>{
  'Weapon_ReloadSpeed': '',
  'Weapon_FireRate': 'RPM',
  'Armor_DamageMitigation': '%',
  'Armor_RadiationCapacity': '',
  'Armor_RadiationDissipation': '',
  'Armor_TemperatureMax': '°C',
  'Armor_TemperatureMin': '°C',
  'Health_MaxHealth': '',
  'ItemResource_PowerGeneration': '',
};
const catalogRawStatUnits = <String, String>{
  'dps': '',
  'damagePerShot': '',
  'rateOfFire': 'RPM',
};

Map<String, String> catalogStats(CatalogRow detail) {
  final result = <String, String>{};
  final raw = catalogObject(detail['weaponRawStats']);
  final rawRate = raw['rateOfFire'];
  for (final (source, units) in [
    ('baseStats', catalogBaseStatUnits),
    ('weaponRawStats', catalogRawStatUnits),
  ]) {
    final row = catalogObject(detail[source]);
    for (final entry in units.entries) {
      // The SCM raw fire rate is the display value when both forms are present.
      if (entry.key == 'Weapon_FireRate' &&
          rawRate is num &&
          rawRate.isFinite) {
        continue;
      }
      final value = row[entry.key];
      if (value is num && value.isFinite) {
        result[entry.key] =
            '$value${entry.value.isEmpty ? '' : ' ${entry.value}'}';
      }
    }
  }
  return result;
}
