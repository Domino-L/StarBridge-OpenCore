import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';

void main() {
  test('same zone keeps the window untouched', () {
    final w = marketShiftWindow(
      [1, 1, 1, 1, 1, 0, 0],
      '19:00',
      '23:00',
      ownerOffset: 480,
      localOffset: 480,
    )!;
    expect(w.days, [1, 1, 1, 1, 1, 0, 0]);
    expect((w.start, w.end), ('19:00', '23:00'));
  });

  test('earlier zone pulls an evening window back across midnight', () {
    // Beijing 16:00–21:00 Mon only, viewed from UTC-6: Mon 02:00–07:00.
    final w = marketShiftWindow(
      [1, 0, 0, 0, 0, 0, 0],
      '16:00',
      '21:00',
      ownerOffset: 480,
      localOffset: -360,
    )!;
    expect(w.days, [1, 0, 0, 0, 0, 0, 0]);
    expect((w.start, w.end), ('02:00', '07:00'));
    // Beijing Mon 09:00 viewed from UTC-6 is Sunday 19:00.
    final early = marketShiftWindow(
      [1, 0, 0, 0, 0, 0, 0],
      '09:00',
      '12:00',
      ownerOffset: 480,
      localOffset: -360,
    )!;
    expect(early.days, [0, 0, 0, 0, 0, 0, 1]);
    expect((early.start, early.end), ('19:00', '22:00'));
  });

  test('later zone pushes a late window into the next day', () {
    // UTC 22:00–23:30 Sunday, viewed from Beijing: Monday 06:00–07:30.
    final w = marketShiftWindow(
      [0, 0, 0, 0, 0, 0, 1],
      '22:00',
      '23:30',
      ownerOffset: 0,
      localOffset: 480,
    )!;
    expect(w.days, [1, 0, 0, 0, 0, 0, 0]);
    expect((w.start, w.end), ('06:00', '07:30'));
  });

  testWidgets(
    'trade window text uses the viewer zone when the owner zone is known',
    (tester) async {
      marketZoneOffsets
        ..clear()
        ..[16] = 480;
      late String converted, unknown;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Builder(
            builder: (context) {
              converted = marketTradeTime(context, {
                'tradeTime': '[1,1,1,1,1,1,1]',
                'tradeStartTime': '16:00',
                'tradeEndTime': '21:00',
                'timezoneId': 16,
              }, localOffset: const Duration(hours: -6));
              unknown = marketTradeTime(context, {
                'tradeTime': '[1,1,1,1,1,1,1]',
                'tradeStartTime': '16:00',
                'tradeEndTime': '21:00',
                'timezoneId': 99,
              }, localOffset: const Duration(hours: -6));
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(converted, '每天 02:00–07:00');
      // Unknown owner zone: shown as SCM returned it, like the SCM website.
      expect(unknown, '每天 16:00–21:00');
      marketZoneOffsets.clear();
    },
  );
}
