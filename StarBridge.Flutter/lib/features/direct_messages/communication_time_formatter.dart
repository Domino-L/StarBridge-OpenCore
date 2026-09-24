import 'package:flutter/widgets.dart';

/// Mirrors Desktop/CommunicationTimeFormatter.cs, including elapsed (not
/// calendar) days, the seven-day boundary, local time and cross-year dates.
String communicationTime(
  DateTime? publishedAt,
  Locale locale, {
  DateTime? now,
}) {
  if (publishedAt == null || publishedAt.isAtSameMomentAs(DateTime.utc(1))) {
    return '';
  }
  final current = now ?? DateTime.now();
  final elapsed = current.difference(publishedAt);
  final english = locale.languageCode == 'en';
  final traditional = locale.countryCode == 'TW' || locale.scriptCode == 'Hant';
  if (elapsed < const Duration(minutes: 1)) {
    return english
        ? 'Just now'
        : traditional
        ? '剛剛'
        : '刚刚';
  }
  if (elapsed < const Duration(hours: 1)) {
    final n = elapsed.inMinutes;
    return english
        ? '$n ${n == 1 ? 'minute' : 'minutes'} ago'
        : '$n${traditional ? '分鐘前' : '分钟前'}';
  }
  if (elapsed < const Duration(days: 1)) {
    final n = elapsed.inHours;
    return english
        ? '$n ${n == 1 ? 'hour' : 'hours'} ago'
        : '$n${traditional ? '小時前' : '小时前'}';
  }
  if (elapsed < const Duration(days: 7)) {
    final n = elapsed.inDays;
    return english ? '$n ${n == 1 ? 'day' : 'days'} ago' : '$n天前';
  }
  final local = publishedAt.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  final year = local.year == current.toLocal().year
      ? ''
      : '${local.year.toString().padLeft(4, '0')}-';
  return '$year${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}';
}
