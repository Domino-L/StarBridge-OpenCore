import 'package:flutter/widgets.dart';

// User 11-14: day 0 reads "今天", day 1 "昨天", counted on the viewer's local
// calendar (the Host converts the relay's whole UTC hour). Never a time of day.
const lastOnlineToday = (hans: '今天', hant: '今天', en: 'today');
const lastOnlineYesterday = (hans: '昨天', hant: '昨天', en: 'yesterday');

int? readLastOnlineDays(Object? value) {
  if (value == null) return null;
  if (value is! int || value < 0 || value > 30) {
    throw const FormatException('Invalid lastOnlineDays');
  }
  return value;
}

/// Local calendar days between [at] and [now]: same local date 0, one local
/// midnight crossed 1, capped at 30; a skewed future time stays 0.
int lastOnlineCalendarDays(DateTime at, DateTime now) {
  final a = at.toLocal();
  final b = now.toLocal();
  final days = DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  return days.clamp(0, 30);
}

int? resolveLastOnlineDays(Map<String, Object?> shared, {DateTime? now}) {
  final days = readLastOnlineDays(shared['lastOnlineDays']);
  if (days != null) return days;
  final raw = shared['lastOnlineAt'];
  final at = raw is String ? DateTime.tryParse(raw) : null;
  return at == null ? null : lastOnlineCalendarDays(at, now ?? DateTime.now());
}

String lastOnlineDaysText(int days, Locale locale, {bool prefix = false}) {
  final chinese = locale.languageCode == 'zh';
  final traditional =
      locale.scriptCode == 'Hant' ||
      locale.countryCode == 'TW' ||
      locale.countryCode == 'HK';
  String pick(({String hans, String hant, String en}) copy) =>
      chinese ? (traditional ? copy.hant : copy.hans) : copy.en;
  final text = days == 0
      ? pick(lastOnlineToday)
      : days == 1
      ? pick(lastOnlineYesterday)
      : days >= 30
      ? (chinese ? '30 天以上' : '30+ days ago')
      : chinese
      ? '$days 天前'
      : '$days days ago';
  return prefix
      ? '${chinese ? (traditional ? '上次在線' : '上次在线') : 'Last online'} $text'
      : text;
}

String offlineWithLastOnline(String label, int? days, Locale locale) =>
    days == null ? label : '$label · ${lastOnlineDaysText(days, locale)}';
