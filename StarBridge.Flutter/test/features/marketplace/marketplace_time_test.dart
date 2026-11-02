import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_time.dart';

void main() {
  test('relative civil dates handle local midnight and year boundaries', () {
    DateTime local(DateTime utc) => utc.subtract(const Duration(hours: 5));
    String? label(String raw, DateTime now) => scmRelativeTime(
      raw,
      now: now,
      today: 'Today',
      yesterday: 'Yesterday',
      localize: local,
    );
    final now = DateTime.parse('2026-01-01T01:00:00-05:00');
    expect(label('2026-01-01 14:02:00', now), 'Today 01:02');
    expect(label('2026-01-01 08:12:00', now), 'Yesterday 19:12');
    expect(label('2025-12-30 08:12:00', now), '2025/12/29 19:12');
    expect(
      label('2026-10-15 08:10:00', DateTime.utc(2026, 10, 17)),
      '10/14 19:10',
    );
    expect(label('invalid', now), isNull);
  });
  test('zone-less SCM receipt deadline is UTC+8 on a UTC-5 device', () {
    const raw = '2026-10-18 10:00:00';
    expect(scmInstant(raw), DateTime.utc(2026, 10, 18, 2));
    final now = DateTime.parse('2026-10-17T00:18:53-05:00');
    final countdown = ScmReceiptCountdown(raw, now);
    expect(countdown.text, '20:41:07');
    expect(countdown.warning, isTrue);
    expect(
      scmLocalTime(
        raw,
        localize: (utc) => utc.subtract(const Duration(hours: 5)),
      ),
      '2026-10-17 21:00',
    );
    expect(
      scmLocalTime(raw, localize: (utc) => utc.add(const Duration(hours: 8))),
      '2026-10-18 10:00',
    );
  });
  test('explicit zones and epoch milliseconds are not shifted twice', () {
    final expected = DateTime.utc(2026, 10, 18, 2);
    for (final raw in [
      '2026-10-18T10:00:00+08:00',
      '2026-10-18T02:00:00Z',
      '2026-10-17T21:00:00-0500',
      expected.millisecondsSinceEpoch,
    ]) {
      expect(scmInstant(raw), expected);
    }
  });
  test(
    'warning boundary, expiry and fractional seconds never show negative time',
    () {
      const raw = '2026-10-18T10:00:00';
      expect(
        ScmReceiptCountdown(raw, DateTime.utc(2026, 10, 17, 2)).warning,
        isFalse,
      );
      expect(
        ScmReceiptCountdown(raw, DateTime.utc(2026, 10, 17, 2, 0, 1)).warning,
        isTrue,
      );
      expect(
        ScmReceiptCountdown(
          raw,
          DateTime.utc(2026, 10, 18, 1, 59, 59, 500),
        ).text,
        '00:00:01',
      );
      for (final now in [
        DateTime.utc(2026, 10, 18, 2),
        DateTime.utc(2026, 10, 19),
      ]) {
        expect(ScmReceiptCountdown(raw, now).text, '00:00:00');
        expect(ScmReceiptCountdown(raw, now).expired, isTrue);
      }
      for (final raw in [
        null,
        '',
        'invalid',
        '2026-02-30 10:00:00',
        '2026-10-18 24:01:00',
      ]) {
        expect(scmInstant(raw), isNull);
        expect(ScmReceiptCountdown(raw, DateTime.now()).text, isNull);
      }
    },
  );
}
