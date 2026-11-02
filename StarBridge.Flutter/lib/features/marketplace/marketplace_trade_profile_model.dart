import 'marketplace_port.dart';

/// Shared validation mirrors SCM's HH:mm, cross-midnight and contact rules.
String? tradeProfileValidation(MarketRow row) {
  final days = row['tradeTime'];
  if (days is! List ||
      days.length != 7 ||
      days.any((v) => v != 0 && v != 1) ||
      !days.contains(1)) {
    return 'trade_profile.no_day';
  }
  int? minutes(Object? raw) {
    if (raw is! String || !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(raw)) {
      return null;
    }
    return int.parse(raw.substring(0, 2)) * 60 + int.parse(raw.substring(3));
  }

  final start = minutes(row['tradeStartTime']),
      end = minutes(row['tradeEndTime']);
  if (start == null || end == null || (end - start + 1440) % 1440 < 60) {
    return 'trade_profile.time_range';
  }
  if ((row['userMobile']?.toString().trim().length ?? 0) < 5) {
    return 'trade_profile.contact_invalid';
  }
  if (row['timezoneId'] is! int || (row['timezoneId'] as int) <= 0) {
    return 'trade_profile.timezone_invalid';
  }
  return null;
}

MarketRow tradeProfileChanges(MarketRow original, MarketRow draft) => {
  for (final key in [
    'tradeTime',
    'tradeStartTime',
    'tradeEndTime',
    'timezoneId',
    'userMobile',
  ])
    key: draft[key],
  for (final key in ['mark', 'language'])
    if (draft[key] != null &&
        draft[key].toString() != (original[key]?.toString() ?? ''))
      key: draft[key].toString(),
};
