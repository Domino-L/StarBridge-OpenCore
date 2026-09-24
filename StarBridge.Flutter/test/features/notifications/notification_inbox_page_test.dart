import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';

import '../friends/social_layout_test.dart' show loadFonts;

class _Inbox extends NotificationInboxController {
  _Inbox() : super(null) {
    ready = true;
    items = [
      InboxItem(
        'a' * 32,
        'system',
        'normal',
        '系统通知示例',
        '通知内容直接展示，不会自动跳转到房间。',
        DateTime(2026, 9, 15),
        false,
        '',
        '',
        true,
      ),
      InboxItem(
        'b' * 32,
        'fleet',
        'action_required',
        '组织加入申请示例',
        '有新的加入申请，请前往组织查看。',
        DateTime(2026, 9, 15),
        false,
        'fleet_applications',
        '',
        true,
      ),
    ];
  }
  @override
  Future<bool> refresh({bool quiet = false, bool reuseFresh = false}) async =>
      true;
}

void main() {
  setUpAll(loadFonts);
  for (final width in [390.0, 1200.0]) {
    testWidgets('inbox categories and filters at $width', (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _Inbox();
      addTearDown(c.dispose);
      final tokens = StyleRegistry()
          .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
          .tokens;
      final boundary = GlobalKey();
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
          theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(body: NotificationInboxPage(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('系统通知示例'), findsOneWidget);
      expect(find.text('组织加入申请示例'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (width == 1200) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/notification-review').create(recursive: true);
          await File('build/notification-review/inbox.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.widgetWithText(ChoiceChip, '待处理'));
      await tester.pumpAndSettle();
      expect(find.text('系统通知示例'), findsNothing);
      expect(find.text('组织加入申请示例'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
