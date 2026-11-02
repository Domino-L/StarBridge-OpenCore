import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/settings/daily_support_port.dart';
import 'package:starbridge_flutter/features/settings/spiritual_support_button.dart';

const thanks = '感谢你在精神上的赞助，你的支持我们已经收到了，这是一些小礼物，记得每天回来领！';
void main() {
  Future<void> open(WidgetTester tester, FakeSupport port) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.runtimeSupportedLocales(),
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: SpiritualSupportButton(port: port)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help-spiritual-support')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'discloses username mail before claim; success requires receipt',
    (tester) async {
      final port = FakeSupport();
      await open(tester, port);
      expect(port.claims, 0);
      expect(find.textContaining('含你用户名字'), findsOneWidget);
      expect(find.text(thanks), findsNothing);
      await tester.tap(find.text('赞助并领取'));
      await tester.pumpAndSettle();
      expect(port.claims, 1);
      expect(find.text(thanks), findsNothing);
      expect(find.text('赞助并领取'), findsNothing);
      port.pending.complete(
        DailySupportResult(
          'granted',
          entitlement: 'overlay.skin.night-shadow',
          expiresAt: DateTime.utc(2026, 10, 11),
          localDay: '2026-10-10',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(thanks), findsOneWidget);
      expect(find.text('夜影 · 24小时体验'), findsOneWidget);
    },
  );
  testWidgets('unknown mutation only offers readback, never automatic retry', (
    tester,
  ) async {
    final port = FakeSupport();
    await open(tester, port);
    await tester.tap(find.text('赞助并领取'));
    port.pending.completeError(StateError('network'));
    await tester.pumpAndSettle();
    expect(find.text(thanks), findsNothing);
    await tester.tap(find.text('查询领取结果'));
    await tester.pumpAndSettle();
    expect(port.claims, 1);
    expect(port.reads, 1);
    expect(find.textContaining('尚未查到'), findsOneWidget);
  });
  for (final outcome in ['thanked', 'alreadyClaimed']) {
    testWidgets('$outcome never claims a new gift', (tester) async {
      final port = FakeSupport();
      await open(tester, port);
      await tester.tap(find.text('赞助并领取'));
      port.pending.complete(DailySupportResult(outcome));
      await tester.pumpAndSettle();
      expect(find.text(thanks), findsNothing);
      expect(port.claims, 1);
    });
  }
  testWidgets('account change discards a late success and clears receipt', (tester) async {
    final port = FakeSupport();
    await open(tester, port);
    await tester.tap(find.text('赞助并领取'));
    port.changed.add(null);
    await tester.pumpAndSettle();
    port.pending.complete(DailySupportResult('granted', entitlement: 'overlay.skin.night-shadow',
        expiresAt: DateTime.utc(2026, 10, 11), localDay: '2026-10-10'));
    await tester.pumpAndSettle();
    expect(find.text(thanks), findsNothing);
    expect(find.textContaining('账号状态已变化'), findsOneWidget);
    expect(find.textContaining('夜影'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await port.changed.close();
  });
  test('rejects gift message without authoritative grant', () {
    expect(
      () => DailySupportResult.parse({
        'schemaVersion': 1,
        'outcome': 'granted',
        'receipt': {'id': 'x', 'localDay': '2026-10-09'},
      }),
      throwsFormatException,
    );
  });
}

class FakeSupport implements DailySupportPort {
  final changed = StreamController<void>.broadcast();
  @override
  Stream<void> get invalidations => changed.stream;
  final pending = Completer<DailySupportResult>();
  int claims = 0, reads = 0;
  @override
  Future<DailySupportResult> claim() {
    claims++;
    return pending.future;
  }

  @override
  Future<DailySupportResult> read() async {
    reads++;
    return const DailySupportResult('ready');
  }
}
