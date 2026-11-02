import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_controller.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_summary.dart';

import '../gameplay_time/gameplay_time_test.dart' as support;
import '../../app/menu_overlay/menu_profiles_session_test.dart'
    show fixtureProfile;

void main() {
  PersonalProfileProjection profile(Object? minutes) =>
      PersonalProfileProjection.fromSnapshot(
        MenuProfileView.parse({
          ...MenuProfileView.encode(fixtureProfile),
          'minutes': minutes,
        }).snapshot!,
      );

  for (final includeLocal in [true, false]) {
    testWidgets('local playtime stays owner-only: $includeLocal', (
      tester,
    ) async {
      final h = support.Harness();
      await tester.pump();
      h.controller.value = const GameplayTimeView(
        seconds: 614 * 3600,
        historicalSeconds: 604 * 3600 + 34 * 60,
      );
      await tester.pumpWidget(
        support.app(
          PersonalProfileSummaryStrip(
            projection: profile(0),
            gameplayTime: h.controller,
            includeLocalTime: includeLocal,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('账号汇总'), includeLocal ? findsNothing : findsOneWidget);
      expect(find.text('本机累计'), includeLocal ? findsOneWidget : findsNothing);
      expect(
        find.text('614小时 0分钟'),
        includeLocal ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('其中日志导入: 604小时 34分钟'),
        includeLocal ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('账号汇总: 0小时 0分钟'),
        includeLocal ? findsOneWidget : findsNothing,
      );
      if (!includeLocal) expect(find.text('0小时 0分钟'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await h.close(tester);
    });
  }
  testWidgets(
    'missing account playtime survives menu transport and never becomes zero',
    (tester) async {
      final projection = profile(null);
      expect(projection.gameplayMinutes, isNull);
      await tester.pumpWidget(
        support.app(
          PersonalProfileSummaryStrip(
            projection: projection,
            includeLocalTime: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('账号汇总'), findsOneWidget);
      expect(find.text('当前页面未提供时长'), findsOneWidget);
      expect(find.text('0小时 0分钟'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('recording visibility choice still hides the metric', (
    tester,
  ) async {
    final h = support.Harness();
    await tester.pump();
    h.controller.value = const GameplayTimeView(
      seconds: 3600,
      showOnProfile: false,
    );
    await tester.pumpWidget(
      support.app(
        PersonalProfileSummaryStrip(
          projection: profile(0),
          gameplayTime: h.controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('账号汇总'), findsNothing);
    expect(find.text('本机累计'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await h.close(tester);
  });
  testWidgets(
    'local ticks update the owner metric without fabricating account totals',
    (tester) async {
      final h = support.Harness();
      await tester.pump();
      final account = profile(90);
      h.controller.value = const GameplayTimeView(seconds: 3600);
      await tester.pumpWidget(
        support.app(
          PersonalProfileSummaryStrip(
            projection: account,
            gameplayTime: h.controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1小时 0分钟'), findsOneWidget);
      h.controller.value = const GameplayTimeView(seconds: 7200);
      await tester.pump();
      expect(find.text('2小时 0分钟'), findsOneWidget);
      expect(find.text('账号汇总: 1小时 30分钟'), findsOneWidget);
      expect(account.gameplayMinutes, 90);
      await tester.pumpWidget(const SizedBox());
      await h.close(tester);
    },
  );
  test(
    'unknown account time survives projection copies and optional menu fields',
    () {
      final encoded = {...MenuProfileView.encode(fixtureProfile)}
        ..remove('minutes');
      final parsed = MenuProfileView.parse(encoded);
      expect(parsed.state, 'ready');
      expect(parsed.snapshot!.gameplayMinutes, isNull);
      expect(
        PersonalProfileProjection.fromSnapshot(parsed.snapshot!)
            .copyWith(about: 'changed')
            .gameplayMinutes,
        isNull,
      );
      expect(MenuProfileView.encode(parsed.snapshot!)['minutes'], isNull);
      expect(
        MenuProfileView.parse({...encoded, 'minutes': -1}).state,
        'unavailable',
      );
    },
  );
}
