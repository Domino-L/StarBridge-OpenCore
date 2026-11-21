import '../../app/localization/app_strings.dart';

final class ContractRecordText {
  const ContractRecordText(this.zhCN, this.zhTW, this.en);
  final String zhCN, zhTW, en;
  String localized(AppStrings strings) => strings.locale.languageCode == 'en'
      ? en
      : strings.locale.countryCode == 'TW' ||
            strings.locale.scriptCode == 'Hant'
      ? zhTW
      : zhCN;
}

Map<String, int> parseAchievementRarity(Object? raw) {
  if (raw is! Map ||
      raw['schemaVersion'] != 1 ||
      raw['windowDays'] != 30 ||
      raw['activeAccounts'] is! int ||
      (raw['activeAccounts'] as int) < 0 ||
      raw['computedAt'] is! String) {
    return const {};
  }
  final at = DateTime.tryParse(raw['computedAt'] as String);
  final values = raw['percentages'];
  if (at == null ||
      !at.isUtc ||
      !at.isAfter(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)) ||
      at.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5))) ||
      values is! Map ||
      values.length > 256 ||
      (raw['activeAccounts'] as int) < 50 && values.isNotEmpty) {
    return const {};
  }
  final result = <String, int>{};
  for (final e in values.entries) {
    if (e.key is! String ||
        !RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(e.key as String) ||
        e.value is! int ||
        (e.value as int) < 0 ||
        (e.value as int) > 10000) {
      return const {};
    }
    result[e.key as String] = e.value as int;
  }
  return result;
}

Map<String, String> parseAchievementTiers(Object? raw) {
  if (raw is! Map) return const {};
  final percentages = parseAchievementRarity(raw);
  final tiers = raw['tiers'];
  if (tiers is! Map || tiers.length > 256) return const {};
  final result = <String, String>{};
  for (final entry in tiers.entries) {
    if (!percentages.containsKey(entry.key) ||
        !const ['rare', 'veryRare'].contains(entry.value)) {
      return const {};
    }
    result[entry.key as String] = entry.value as String;
  }
  return result;
}

Map<String, ContractRecordText> parseContractRecords(Object? raw) {
  if (raw is! Map || raw.length > 5) return const {};
  final result = <String, ContractRecordText>{};
  for (final e in raw.entries) {
    if (!const [
      'contract-first',
      'contract-tsg-lead',
      'contract-tsg-complete',
      'contract-tsg-swift',
      'contract-tsg-deathless',
    ].contains(e.key)) {
      return const {};
    }
    final value = e.value;
    bool valid(Object? text) =>
        text is String &&
        text.trim().isNotEmpty &&
        text.length <= 512 &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(text);
    if (value is! Map ||
        !valid(value['zhCN']) ||
        !valid(value['zhTW']) ||
        !valid(value['en'])) {
      return const {};
    }
    result[e.key as String] = ContractRecordText(
      value['zhCN'] as String,
      value['zhTW'] as String,
      value['en'] as String,
    );
  }
  return result;
}
