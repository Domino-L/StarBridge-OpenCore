/// SCM's zone-less timestamps are Beijing civil time (UTC+08:00), confirmed
/// by the service team. Never interpret them in the device's time zone.
DateTime? scmInstant(Object? raw) {
  if (raw is num && raw.isFinite) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true);
    } on ArgumentError {
      return null;
    }
  }
  if (raw is! String) return null;
  final value = raw.trim();
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?(Z|[+-]\d{2}:?\d{2})?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return null;
  final fields = [
    for (var i = 1; i <= 6; i++) int.parse(match.group(i) ?? '0'),
  ];
  final check = DateTime.utc(
    fields[0],
    fields[1],
    fields[2],
    fields[3],
    fields[4],
    fields[5],
  );
  if (check.year != fields[0] ||
      check.month != fields[1] ||
      check.day != fields[2] ||
      check.hour != fields[3] ||
      check.minute != fields[4] ||
      check.second != fields[5]) {
    return null;
  }
  return DateTime.tryParse(match.group(7) == null ? '$value+08:00' : value)
      ?.toUtc();
}

String? scmLocalTime(Object? raw, {DateTime Function(DateTime)? localize}) {
  final instant = scmInstant(raw);
  if (instant == null) return null;
  final local = localize?.call(instant) ?? instant.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class ScmReceiptCountdown {
  ScmReceiptCountdown(Object? deadline, DateTime now)
    : remaining = scmInstant(deadline)?.difference(now.toUtc());
  final Duration? remaining;
  bool get expired => remaining != null && remaining! <= Duration.zero;
  bool get warning =>
      remaining != null && remaining! < const Duration(hours: 24);
  String? get text {
    if (remaining == null) return null;
    if (expired) return '00:00:00'; // UI renders the localized overdue state.
    // Round up partial seconds so an unexpired deadline never reads 00:00:00.
    final seconds = (remaining!.inMicroseconds + 999999) ~/ 1000000;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
  }
}

/// Compare civil dates after the same local conversion; avoid 24-hour DST assumptions.
String? scmRelativeTime(
  Object? raw, {
  required DateTime now,
  required String today,
  required String yesterday,
  DateTime Function(DateTime)? localize,
}) {
  final instant = scmInstant(raw);
  if (instant == null) return null;
  DateTime convert(DateTime value) =>
      localize?.call(value.toUtc()) ?? value.toLocal();
  final local = convert(instant), current = convert(now);
  final date = DateTime.utc(local.year, local.month, local.day);
  final currentDate = DateTime.utc(current.year, current.month, current.day);
  String two(int value) => value.toString().padLeft(2, '0');
  final prefix = date == currentDate
      ? today
      : date == currentDate.subtract(const Duration(days: 1))
      ? yesterday
      : local.year == current.year
      ? '${local.month}/${local.day}'
      : '${local.year}/${local.month}/${local.day}';
  return '$prefix ${two(local.hour)}:${two(local.minute)}';
}
