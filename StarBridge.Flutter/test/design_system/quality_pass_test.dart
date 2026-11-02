import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_timed_snack_bar.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/typography/cjk_line_break.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

// 界面打磨八条（用户 2026-10-29 选"全A"）里可以自动验证的部分。
ThemeData _theme(AppearanceMode mode) => buildStarBridgeTheme(
  StyleRegistry().resolve(AppPreferences.defaults.designStyleId, mode).tokens,
  const Locale('zh', 'CN'),
);

void main() {
  group('① 数字等宽 · ④ 深色字重', () {
    test('基础字样都打开等宽数字', () {
      final text = _theme(AppearanceMode.dark).textTheme;
      for (final style in [
        text.bodyMedium,
        text.bodySmall,
        text.titleMedium,
        text.labelLarge,
      ]) {
        expect(
          style!.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
    });

    test('深色：正文 380、标题 560；浅色保持 400 / 600', () {
      final dark = _theme(AppearanceMode.dark).textTheme;
      final light = _theme(AppearanceMode.light).textTheme;
      final bodyLight = light.bodyMedium!.fontWeight!.value;
      final titleLight = light.titleLarge!.fontWeight!.value;
      expect(dark.bodyMedium!.fontWeight!.value, bodyLight - 20);
      expect(dark.titleLarge!.fontWeight!.value, titleLight - 40);
      expect(bodyLight, 400);
    });
  });

  group('③ 防孤字', () {
    test('最后两个汉字粘在一起，句号跟着走', () {
      final out = keepLastTwo('成员在上屏和浮层里都能看到信息。');
      expect(out, '成员在上屏和浮层里都能看到信⁠息⁠。');
      expect(out.replaceAll('⁠', ''), '成员在上屏和浮层里都能看到信息。');
    });

    test('结尾不是两个汉字时原样返回', () {
      expect(keepLastTwo('Trade 24'), 'Trade 24');
      expect(keepLastTwo('A字'), 'A字');
      expect(keepLastTwo(''), '');
    });

    test('元信息只在"·"处断开', () {
      expect(
        metaLine(['工作日 19:00-22:30', ' 周末 08:00-22:00 ', '', 'UTC-06:00']),
        '工作日 19:00‑22:30 · 周末 08:00‑22:00 · '
        'UTC‑06:00',
      );
    });
  });

  group('② 临时反馈自动消失', () {
    Future<ScaffoldMessengerState> pump(
      WidgetTester tester, {
      bool accessible = false,
      bool reduce = false,
    }) async {
      final key = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            accessibleNavigation: accessible,
            disableAnimations: reduce,
          ),
          child: MaterialApp(
            theme: _theme(AppearanceMode.dark),
            scaffoldMessengerKey: key,
            home: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );
      return key.currentState!;
    }

    testWidgets('2.5 秒后自己收起，原因是 timeout，带剩余时间细线', (tester) async {
      final messenger = await pump(tester);
      final closed = messenger
          .showSnackBar(starBridgeTimedSnackBar(content: const Text('已复制')))
          .closed;
      SnackBarClosedReason? reason;
      closed.then((r) => reason = r);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('已复制'), findsOneWidget);
      expect(
        find.byKey(const Key('timed-snack-bar-remaining')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.text('已复制'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('已复制'), findsNothing);
      expect(reason, SnackBarClosedReason.timeout);
    });

    testWidgets('鼠标停在上面时暂停，移开后继续', (tester) async {
      final messenger = await pump(tester);
      messenger.showSnackBar(
        starBridgeTimedSnackBar(
          content: const Text('已取消关注'),
          action: SnackBarAction(label: '撤销', onPressed: () {}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('已取消关注')));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('已取消关注'), findsOneWidget, reason: '悬停中不收起');
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('已取消关注'), findsOneWidget, reason: '剩余约 2.1 秒');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('已取消关注'), findsNothing);
    });

    testWidgets('读屏导航开着时不自动收起', (tester) async {
      final messenger = await pump(tester, accessible: true);
      messenger.showSnackBar(
        starBridgeTimedSnackBar(content: const Text('已复制')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('已复制'), findsOneWidget);
    });

    testWidgets('减少动态效果：照样收起，但不画倒计时细线', (tester) async {
      final messenger = await pump(tester, reduce: true);
      messenger.showSnackBar(
        starBridgeTimedSnackBar(content: const Text('已复制')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('timed-snack-bar-remaining')), findsNothing);
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pumpAndSettle();
      expect(find.text('已复制'), findsNothing);
    });
  });

  test('⑤ 四套风格的小控件切换都在 160–200 毫秒', () {
    for (final suite in InteractionSuite.values) {
      final ms = SuiteMotion.of(suite).select.inMilliseconds;
      expect(ms, inInclusiveRange(160, 200), reason: suite.name);
    }
  });
}
