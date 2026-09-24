import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/communication_time_formatter.dart';

void main() {
  const cn = Locale('zh', 'CN');
  final now = DateTime(2026, 9, 7, 12, 30);
  test('WPF communication relative time exact boundaries', () {
    String format(Duration age) =>
        communicationTime(now.subtract(age), cn, now: now);
    expect(communicationTime(null, cn, now: now), '');
    expect(communicationTime(DateTime.utc(1), cn, now: now), '');
    expect(format(const Duration(seconds: -1)), '刚刚');
    expect(format(Duration.zero), '刚刚');
    expect(format(const Duration(seconds: 59)), '刚刚');
    expect(format(const Duration(minutes: 1)), '1分钟前');
    expect(format(const Duration(minutes: 59, seconds: 59)), '59分钟前');
    expect(format(const Duration(hours: 1)), '1小时前');
    expect(format(const Duration(hours: 23, minutes: 59)), '23小时前');
    expect(format(const Duration(days: 1)), '1天前');
    expect(format(const Duration(days: 6, hours: 23)), '6天前');
    expect(format(const Duration(days: 7)), '08-31 12:30');
  });
  test(
    'WPF absolute time uses local date and includes year only across years',
    () {
      expect(
        communicationTime(DateTime(2026, 8, 1, 9, 5).toUtc(), cn, now: now),
        '08-01 09:05',
      );
      expect(
        communicationTime(DateTime(2025, 12, 31, 23, 8).toUtc(), cn, now: now),
        '2025-12-31 23:08',
      );
      final midnight = DateTime(2026, 9, 7, 0, 1);
      expect(
        communicationTime(DateTime(2026, 9, 6, 23, 59), cn, now: midnight),
        '2分钟前',
      );
    },
  );
  test('same communication rules in traditional Chinese and English', () {
    expect(communicationTime(now, const Locale('zh', 'TW'), now: now), '剛剛');
    expect(
      communicationTime(
        now.subtract(const Duration(hours: 2)),
        const Locale('zh', 'TW'),
        now: now,
      ),
      '2小時前',
    );
    expect(communicationTime(now, const Locale('en'), now: now), 'Just now');
    expect(
      communicationTime(
        now.subtract(const Duration(minutes: 1)),
        const Locale('en'),
        now: now,
      ),
      '1 minute ago',
    );
    expect(
      communicationTime(
        now.subtract(const Duration(days: 2)),
        const Locale('en'),
        now: now,
      ),
      '2 days ago',
    );
  });
}
