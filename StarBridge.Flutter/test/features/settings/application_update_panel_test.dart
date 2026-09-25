import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/application_update_dialog.dart';
import 'package:starbridge_flutter/features/settings/application_update_status.dart';

import '../friends/social_layout_test.dart' show capture, loadFonts, size;

void main() {
  setUpAll(loadFonts);
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final mode in AppearanceMode.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'announcement actions stay visible at 390px $locale $mode $scale',
          (tester) async {
            size(tester, const Size(390, 540));
            await tester.pumpWidget(
              preview(locale, mode, scale, longNotes: true),
            );
            await tester.pumpAndSettle();
            final button = find.byType(FilledButton);
            expect(button.hitTestable(), findsOneWidget);
            expect(tester.getRect(button).bottom, lessThanOrEqualTo(540));
            expect(find.textContaining('##'), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
  testWidgets('desktop announcement preview', (tester) async {
    size(tester, const Size(1280, 800));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: preview(const Locale('zh', 'CN'), AppearanceMode.dark, 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('优化'), findsOneWidget);
    expect(find.text('修复'), findsOneWidget);
    expect(find.textContaining('##'), findsNothing);
    await capture(tester, boundary, 'startup-update-announcement');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'installation unavailable gives recovery guidance, not an unopened feature',
    (tester) async {
      await tester.pumpWidget(
        preview(
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
          1,
          installable: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('官网下载'), findsOneWidget);
      expect(find.textContaining('尚未开放'), findsNothing);
      expect(find.text('下载更新'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Widget preview(
  Locale locale,
  AppearanceMode mode,
  double scale, {
  bool longNotes = false,
  bool installable = true,
}) {
  const notes =
      '本次更新改进旧版升级后的衔接，修复桌面图标和共享设置的状态反馈。\n\n'
      '## 优化\n- 新版正常启动后，自动整理已确认的旧安装，接替桌面、开始菜单和原有开机启动入口。\n'
      '- 实时状态共享的正常后台刷新保持静默，不再反复显示“正在应用”。\n\n'
      '## 修复\n- 修复桌面快捷方式沿用旧版带底色图标的问题。\n'
      '- 修复首次好友共享设置实际已保存、但回执中断后仍提示未确认的问题。\n\n'
      '## 使用须知\n- 保留信息浮层，不提供菜单浮层。账号和本地资料保留。';
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: buildStarBridgeTheme(FutureRestraintStyle.resolve(mode), locale),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: ApplicationUpdateDialog(
        startupAnnouncement: true,
        initialStatus: ApplicationUpdateStatus.parse({
          'schemaVersion': 1,
          'state': 'available',
          'currentVersion': '0.7.0.1',
          'availableVersion': '0.7.0.2',
          'notes': longNotes ? List.filled(12, notes).join('\n') : notes,
        }),
        prepare: installable
            ? (_) async => throw StateError('Preview never installs')
            : null,
      ),
    ),
  );
}
