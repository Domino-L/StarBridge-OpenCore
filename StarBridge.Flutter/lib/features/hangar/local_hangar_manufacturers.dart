import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'local_hangar_copy.dart';
import 'local_hangar_port.dart';

/// A known ship maker: names per language, and the file name of its mark in the
/// official package. Display only; never ownership or ship identity.
final class LocalHangarManufacturer {
  const LocalHangarManufacturer(
    this.key,
    this.cn,
    this.tw,
    this.en,
    this.enShort, {
    this.logo = true,
    this.aliases = const [],
  });
  final String key, cn, tw, en, enShort;

  /// The Fan Kit carries no mark for this maker; it stays text everywhere.
  final bool logo;
  final List<String> aliases;

  /// For section titles and the stage.
  String name(LocalHangarCopy c) => c.pick(cn, tw, en);

  /// For the second line of a card.
  String short(LocalHangarCopy c) => c.pick(cn, tw, enShort);

  /// The original name beside a Chinese one; nothing when it would repeat.
  String? original(LocalHangarCopy c) => name(c) == en ? null : en;
}

abstract final class LocalHangarManufacturers {
  static const all = [
    LocalHangarManufacturer(
      'aegis',
      '圣盾',
      '聖盾',
      'Aegis Dynamics',
      'Aegis',
      aliases: ['aegis', 'aegs'],
    ),
    LocalHangarManufacturer(
      'anvil',
      '铁砧',
      '鐵砧',
      'Anvil Aerospace',
      'Anvil',
      aliases: ['anvil', 'anvl'],
    ),
    LocalHangarManufacturer(
      'aopoa',
      '奥波亚',
      '奧波亞',
      'Aopoa',
      'Aopoa',
      aliases: ['xian', "xi'an", 'xnaa'],
    ),
    LocalHangarManufacturer(
      'argo',
      '南船座',
      '南船座',
      'Argo Astronautics',
      'Argo',
      aliases: ['argo'],
    ),
    LocalHangarManufacturer('banu', '巴努', '巴努', 'Banu', 'Banu'),
    LocalHangarManufacturer(
      'consolidated-outland',
      '联合外域',
      '聯合外域',
      'Consolidated Outland',
      'Consolidated',
      aliases: ['cnou'],
    ),
    LocalHangarManufacturer(
      'crusader',
      '十字军',
      '十字軍',
      'Crusader Industries',
      'Crusader',
      aliases: ['crusader', 'crus'],
    ),
    LocalHangarManufacturer(
      'drake',
      '德雷克',
      '德雷克',
      'Drake Interplanetary',
      'Drake',
      aliases: ['drake', 'drak'],
    ),
    LocalHangarManufacturer(
      'esperia',
      '埃斯佩里亚',
      '埃斯佩里亞',
      'Esperia',
      'Esperia',
      aliases: ['espr'],
    ),
    LocalHangarManufacturer(
      'gatac',
      '盖塔克',
      '蓋塔克',
      'Gatac Manufacture',
      'Gatac',
      aliases: ['gatac'],
    ),
    LocalHangarManufacturer(
      'greycat',
      '灰猫',
      '灰貓',
      'Greycat Industrial',
      'Greycat',
      logo: false,
      aliases: ['greycat', 'grin'],
    ),
    LocalHangarManufacturer(
      'greys',
      '格雷黑市',
      '格雷黑市',
      "Grey's Market",
      "Grey's",
      logo: false,
      aliases: ["grey's", 'greys'],
    ),
    LocalHangarManufacturer(
      'kruger',
      '克鲁格',
      '克魯格',
      'Kruger Intergalactic',
      'Kruger',
      aliases: ['kruger', 'krig'],
    ),
    LocalHangarManufacturer(
      'misc',
      '武藏',
      '武藏',
      'MISC',
      'MISC',
      aliases: ['musashi', 'musashi industrial and starflight concern'],
    ),
    LocalHangarManufacturer(
      'mirai',
      '未来',
      '未來',
      'Mirai',
      'Mirai',
      aliases: ['mrai'],
    ),
    LocalHangarManufacturer(
      'origin',
      '起源',
      '起源',
      'Origin Jumpworks',
      'Origin',
      aliases: ['origin', 'orig'],
    ),
    LocalHangarManufacturer(
      'rsi',
      'RSI',
      'RSI',
      'Roberts Space Industries',
      'RSI',
      aliases: ['rsi'],
    ),
    LocalHangarManufacturer(
      'tumbril',
      '盾博尔',
      '盾博爾',
      'Tumbril Land Systems',
      'Tumbril',
      aliases: ['tumbril', 'tmbl'],
    ),
    LocalHangarManufacturer(
      'vanduul',
      '剜度',
      '剜度',
      'Vanduul',
      'Vanduul',
      logo: false,
      aliases: ['vncl'],
    ),
  ];

  static final _index = <String, LocalHangarManufacturer>{
    for (final maker in all) ...{
      maker.en.toLowerCase(): maker,
      maker.enShort.toLowerCase(): maker,
      for (final alias in maker.aliases) alias: maker,
    },
  };

  static LocalHangarManufacturer? find(String? value) =>
      _index[value?.trim().toLowerCase()];

  /// The catalog's maker first; an RSI liner only when it names a known maker,
  /// because it can carry other text.
  static LocalHangarManufacturer? of(LocalHangarShip ship) =>
      find(ship.manufacturer) ?? find(ship.liner);

  /// A maker the table does not know keeps its catalog spelling.
  static String? unknownName(LocalHangarShip ship) {
    final raw = ship.manufacturer?.trim();
    return of(ship) == null && raw?.isNotEmpty == true ? raw : null;
  }

  /// Every spelling a search should match, whatever the current language.
  static Iterable<String> searchNames(LocalHangarShip ship) sync* {
    if (ship.manufacturer != null) yield ship.manufacturer!;
    final maker = of(ship);
    if (maker == null) return;
    yield maker.cn;
    yield maker.tw;
    yield maker.en;
    yield maker.enShort;
    yield* maker.aliases;
  }
}

/// Official marks ship only in the official package. Public source has no such
/// files, so every place that shows a mark already reads as text without it.
final class LocalHangarMakerLogos {
  LocalHangarMakerLogos._();
  static final instance = LocalHangarMakerLogos._();
  static final _isTestRun = Platform.environment.containsKey('FLUTTER_TEST');

  Set<String> _assets = const {};
  Future<void>? _loading;

  static String asset(String key, {required bool dark}) =>
      'assets/ships/catalog-maker-$key-${dark ? 'dark' : 'light'}.png';

  bool has(LocalHangarManufacturer maker, {required bool dark}) =>
      maker.logo && _assets.contains(asset(maker.key, dark: dark));

  /// Reads the bundle's file list once. A failure means no marks, only text.
  Future<void> ensureLoaded() {
    if (_isTestRun) return Future.value();
    return _loading ??= () async {
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        _assets = manifest
            .listAssets()
            .where((path) => path.startsWith('assets/ships/catalog-maker-'))
            .toSet();
      } on Object {
        _assets = const {};
      }
    }();
  }

  void debugUse(Set<String> assets) => _assets = assets;
}
