import 'package:flutter/widgets.dart';

import 'catalog_port.dart';

// Our own Chinese names for values the SCM catalog sends without a Chinese
// field (user 11-11: "还有很多英语，我选的是中文"). English UIs keep the SCM
// English. Unknown values fall back to the SCM text; nothing is guessed from
// partial words.

/// Mission types (SCM `missionType`): (Simplified, Traditional).
const catalogMissionTypeNames = <String, (String, String)>{
  'Bounty Hunter': ('赏金猎人', '賞金獵人'),
  'Collection': ('收集', '收集'),
  'Courier': ('快递', '快遞'),
  'Delivery': ('运送', '運送'),
  'Ground Vehicle Mining': ('地面载具采矿', '地面載具採礦'),
  'Hand Mining': ('手持采矿', '手持採礦'),
  'Hauling': ('货运', '貨運'),
  'Hauling - Interstellar': ('货运 - 跨星系', '貨運 - 跨星系'),
  'Hauling - Local': ('货运 - 本地', '貨運 - 本地'),
  'Hauling - Planetary': ('货运 - 行星', '貨運 - 行星'),
  'Hauling - Stellar': ('货运 - 星系内', '貨運 - 星系內'),
  'Investigation': ('调查', '調查'),
  'Maintenance': ('维护', '維護'),
  'Mercenary': ('雇佣兵', '傭兵'),
  'Other': ('其他', '其他'),
  'Priority': ('优先', '優先'),
  'PvP Missions': ('PvP 任务', 'PvP 任務'),
  'Refueling': ('加油', '加油'),
  'RSI Discovery Event': ('RSI 探索活动', 'RSI 探索活動'),
  'Salvage': ('打捞', '打撈'),
  'Ship Mining': ('舰船采矿', '艦船採礦'),
  'Wikelo - Other Items': ('维克洛 - 其他物品', '維克洛 - 其他物品'),
  'Wikelo - Vehicles': ('维克洛 - 载具', '維克洛 - 載具'),
  'local': ('本地', '本地'),
};

/// Item kinds: SCM puts the item code prefix (wep, cool, nozzle…) in the
/// blueprint `manufacturer` field; it is not a manufacturer.
/// (Simplified, Traditional, English).
const catalogBlueprintKindNames = <String, (String, String, String)>{
  'wep': ('武器', '武器', 'Weapon'),
  'cool': ('冷却器', '冷卻器', 'Cooler'),
  'powr': ('电源', '電源', 'Power plant'),
  'shld': ('护盾', '護盾', 'Shield'),
  'qdrv': ('量子引擎', '量子引擎', 'Quantum drive'),
  'jdrv': ('跃迁引擎', '躍遷引擎', 'Jump drive'),
  'radr': ('雷达', '雷達', 'Radar'),
  'misl': ('导弹', '導彈', 'Missile'),
  'mrck': ('导弹架', '導彈架', 'Missile rack'),
  'turr': ('炮塔', '砲塔', 'Turret'),
  'nozzle': ('喷口', '噴口', 'Nozzle'),
  'carryable': ('可携带物品', '可攜帶物品', 'Carryable'),
  'ammo': ('弹药', '彈藥', 'Ammo'),
  'armr': ('装甲', '裝甲', 'Armor'),
  'fuel': ('燃料', '燃料', 'Fuel'),
};

bool _traditional(Locale locale) =>
    locale.scriptCode == 'Hant' ||
    const {'TW', 'HK', 'MO'}.contains(locale.countryCode);

/// Mission type for display: SCM Chinese first, then our table, then SCM text.
String catalogMissionType(
  CatalogRow row,
  Locale locale, [
  String field = 'missionType',
]) {
  final en = row[field]?.toString().trim() ?? '';
  if (locale.languageCode == 'en') return en.isEmpty ? '—' : en;
  final cn = row['${field}Cn']?.toString().trim() ?? '';
  if (cn.isNotEmpty) return cn;
  return catalogMissionTypeLabel(en, locale);
}

/// A bare mission type value: our table for Chinese UIs, else [fallback]
/// (the SCM label), else the value itself.
String catalogMissionTypeLabel(
  String value,
  Locale locale, {
  String? fallback,
}) {
  final shown = fallback?.trim().isNotEmpty == true ? fallback!.trim() : value;
  if (value.isEmpty) return shown.isEmpty ? '—' : shown;
  if (locale.languageCode == 'en') return shown;
  final names = catalogMissionTypeNames[value];
  if (names == null) return shown;
  return _traditional(locale) ? names.$2 : names.$1;
}

/// Item kind label. Chinese UIs get our label, or null for an unknown code
/// (never a raw code on cards); English UIs keep the SCM value as before.
String? catalogBlueprintKind(Object? code, Locale locale) {
  final raw = code?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  if (locale.languageCode == 'en') return raw;
  final names = catalogBlueprintKindNames[raw.toLowerCase()];
  if (names == null) return null;
  return _traditional(locale) ? names.$2 : names.$1;
}

/// Filter label for a kind code: the known label, else the code.
String catalogBlueprintKindLabel(String code, Locale locale) =>
    catalogBlueprintKind(code, locale) ?? code;

final _size = RegExp(r'^S0*(\d{1,2})$', caseSensitive: false);

/// Blueprint title for display. Chinese UIs without an SCM Chinese name drop a
/// leading word that repeats the item kind code and lift a size word (S1,
/// S04) into [size]; other words keep their order and spelling. English UIs
/// and SCM Chinese names are unchanged.
({String name, String? size}) catalogBlueprintTitle(
  CatalogRow row,
  Locale locale,
) {
  final en = row['blueprintName']?.toString().trim() ?? '';
  if (locale.languageCode == 'en') {
    return (name: en.isEmpty ? '—' : en, size: null);
  }
  final cn = row['blueprintNameCn']?.toString().trim() ?? '';
  if (cn.isNotEmpty) return (name: cn, size: null);
  if (en.isEmpty) return (name: '—', size: null);
  final words = en.split(RegExp(r'\s+'));
  final kind = row['manufacturer']?.toString().trim().toLowerCase() ?? '';
  if (kind.isNotEmpty && words.first.toLowerCase() == kind) {
    words.removeAt(0);
  }
  String? size;
  final index = words.indexWhere(_size.hasMatch);
  // More than one size word is ambiguous: keep the words as sent.
  if (index >= 0 && words.where(_size.hasMatch).length == 1) {
    size = 'S${_size.firstMatch(words[index])!.group(1)}';
    words.removeAt(index);
  }
  final name = words.join(' ');
  return name.isEmpty ? (name: en, size: null) : (name: name, size: size);
}

/// One-line title for compact places (recent list): "name · S1".
String catalogBlueprintTitleLine(CatalogRow row, Locale locale) {
  final title = catalogBlueprintTitle(row, locale);
  return title.size == null ? title.name : '${title.name} · ${title.size}';
}
