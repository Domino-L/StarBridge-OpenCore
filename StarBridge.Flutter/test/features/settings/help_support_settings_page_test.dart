import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:starbridge_flutter/app/legal/starbridge_third_party_licenses.dart';
import 'package:starbridge_flutter/app/legal/third_party_license_browser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/help_support_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/brand/scm_brand_mark.dart';
import 'package:starbridge_flutter/design_system/brand/starbridge_app_icon.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/help_support_settings_page.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';
import 'package:starbridge_flutter/features/settings/settings_page.dart';
import 'package:starbridge_flutter/features/settings/help_support_port.dart';
import 'package:starbridge_flutter/features/settings/spiritual_support_button.dart';

import 'daily_support_test.dart' show FakeSupport;
import 'package:starbridge_flutter/features/settings/help_support_live_content.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main() {
  // User 11-10: "不展示这个按钮". The help page no longer shows daily support;
  // the button itself is still tested directly below.
  testWidgets('help page does not show the daily support button', (tester) async {
    final support = FakeSupport();
    addTearDown(support.changed.close);
    await tester.pumpWidget(
      _app(HelpSupportSettingsPage(port: _ScmLinkFake(), dailySupport: support)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-spiritual-support')), findsNothing);
    expect(find.byKey(const Key('help-scm-team')), findsOneWidget);
    // Without the button nothing reads, claims or listens to daily support.
    expect((support.claims, support.reads), (0, 0));
    expect(support.changed.hasListener, isFalse);
  });
  testWidgets('spiritual support never opens payment or claims an unissued trial', (tester) async {
    await tester.pumpWidget(_app(const SpiritualSupportButton()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help-spiritual-support')));
    await tester.pumpAndSettle();
    expect(find.text('我们已经收到你的精神赞助，谢谢你！'), findsOneWidget);
    expect(find.textContaining('当前尚未发放体验'), findsNothing);
    expect(find.text('无需付款，也不会打开支付页面。'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets('spiritual support opens and dismisses locally in $locale', (tester) async {
      await tester.pumpWidget(_app(const SpiritualSupportButton(), locale: locale));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('help-spiritual-support')));
      await tester.pumpAndSettle();
      final text = locale.languageCode == 'en'
          ? 'Your moral support means a lot. Thank you!'
          : locale.countryCode == 'TW'
          ? '我們已經收到你的精神贊助，謝謝你！'
          : '我们已经收到你的精神赞助，谢谢你！';
      expect(find.text(text), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('full product release history remains readable in $locale', (
      tester,
    ) async {
      final catalog = jsonDecode(
        File('../release-notes/catalog.json').readAsStringSync(),
      ) as Map;
      final entry = (catalog['entries'] as List).firstWhere(
        (e) => e['version'] == '0.7.0',
      ) as Map;
      final port = _SupportFake()..historyEntries = [entry];
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: HelpSupportReadCard(name: 'helpSupport.history', port: port),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      final title = locale.languageCode == 'en'
          ? 'Release history'
          : locale.countryCode == 'TW'
          ? '版本記錄'
          : '版本记录';
      expect(find.text(title), findsOneWidget);
      await tester.tap(find.text('v0.7.0 · ${entry['title']}'));
      await tester.pumpAndSettle();
      expect(find.text(entry['summary'] as String), findsOneWidget);
      final last = '• ${(entry['highlights'] as List).last}';
      await tester.ensureVisible(find.text(last));
      await tester.pumpAndSettle();
      expect(find.text(last), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('SCM affiliation opens website only on click', (tester) async {
    final port = _ScmLinkFake();
    await tester.pumpWidget(_app(HelpSupportSettingsPage(port: port)));
    await tester.pumpAndSettle();
    expect(find.textContaining('旗下应用'), findsNothing);
    final logoAssets = tester
        .widgetList<Image>(
          find.descendant(
            of: find.byKey(const Key('help-scm-team')),
            matching: find.byType(Image),
          ),
        )
        .map((image) => (image.image as AssetImage).assetName);
    expect(
      logoAssets,
      containsAll([
        'assets/brand/scm_mark.png',
        'assets/brand/scm_wordmark.png',
      ]),
    );
    expect(port.calls, 0);
    await tester.tap(find.byKey(const Key('help-scm-team')));
    await tester.pumpAndSettle();
    expect(port.calls, 1);
    expect(tester.takeException(), isNull);
  });
  for (final count in <Object?>[null, 0, 42, -1, 'invalid']) {
    testWidgets('registered accounts distinguish unknown and zero: $count', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: HelpSupportReadCard(
              name: 'helpSupport.stats',
              port: _SupportFake()..accountCount = count,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('星桥注册账号数'), findsOneWidget);
      expect(find.text('社区组织数量'), findsOneWidget);
      expect(find.text('仅统计星桥注册账号，暂不包含 SCM 账号。'), findsOneWidget);
      if (count is int && count >= 0) {
        expect(find.text('$count'), findsOneWidget);
        expect(find.text('暂不可用'), findsNothing);
      } else {
        expect(find.text('暂不可用'), findsOneWidget);
        expect(find.text('0'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
  // User 11-07: "现在星桥注册账户数改成用户数，统计有多少SCM登录账号". The
  // label changes only with a real SCM user count, so it never names a
  // number the service did not send.
  for (final users in <Object?>[7, 0, null, -1, 'invalid']) {
    testWidgets('SCM user count replaces registered accounts: $users', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: HelpSupportReadCard(
              name: 'helpSupport.stats',
              port: _SupportFake()
                ..accountCount = 42
                ..scmUserCount = users,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shown = users is int && users >= 0;
      expect(find.text('用户数'), shown ? findsOneWidget : findsNothing);
      expect(find.text('星桥注册账号数'), shown ? findsNothing : findsOneWidget);
      expect(
        find.text('统计用 SCM 账号登录过星桥的用户。'),
        shown ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('仅统计星桥注册账号，暂不包含 SCM 账号。'),
        shown ? findsNothing : findsOneWidget,
      );
      expect(find.text(shown ? '$users' : '42'), findsOneWidget);
      expect(find.text(shown ? '42' : '7'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final (locale, label) in [
    (const Locale('zh', 'TW'), '使用者數'),
    (const Locale('en', 'US'), 'Users'),
  ]) {
    testWidgets('SCM user count fits a narrow window in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: HelpSupportReadCard(
              name: 'helpSupport.stats',
              port: _SupportFake()..scmUserCount = 7,
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final mode in [AppearanceMode.light, AppearanceMode.dark]) {
      testWidgets('support live cards fit narrow layout $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _app(
            HelpSupportSettingsPage(
              initialTopic: HelpSupportTopic.updates,
              port: _SupportFake(),
            ),
            locale: locale,
            mode: mode,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final recoveryAdvice = switch (locale.countryCode) {
          'CN' => '更新安装中途中断时，请直接用完整安装包安装最新版，不要装回旧版本。',
          'TW' => '更新安裝中途中斷時，請直接用完整安裝包安裝最新版，不要裝回舊版本。',
          _ => 'If an update installation is interrupted, use the full installer to install the latest version. Do not reinstall an older version.',
        };
        expect(find.textContaining(recoveryAdvice), findsOneWidget);
        final retirementAdvice = switch (locale.countryCode) {
          'CN' => '并保留其中的文件，让后续更新可以继续准备。',
          'TW' => '並保留其中的檔案，讓後續更新可以繼續準備。',
          _ => 'keeping their files so the next update can proceed.',
        };
        expect(find.textContaining(retirementAdvice), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('help-topic-button-feedback')),
        );
        await tester.tap(find.byKey(const Key('help-topic-button-feedback')));
        await tester.pumpAndSettle();
        final expectedScope = switch (locale.countryCode) {
          'CN' => '提出建议或功能需求时',
          'TW' => '提出建議或功能需求時',
          _ => 'suggestion or feature request',
        };
        expect(find.textContaining(expectedScope), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'reads real states and product history without showing invented stats',
    (tester) async {
      final port = _SupportFake();
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: Column(
              children: [
                HelpSupportReadCard(
                  name: 'applicationUpdates.check',
                  port: port,
                ),
                HelpSupportReadCard(name: 'helpSupport.history', port: port),
                HelpSupportReadCard(name: 'helpSupport.stats', port: port),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('在线更新来源'), findsOneWidget);
      expect(find.text('版本记录'), findsOneWidget);
      expect(find.textContaining('旧版客户端'), findsNothing);
      expect(find.textContaining('WPF'), findsNothing);
      expect(find.textContaining('v0.6.6'), findsOneWidget);
      expect(find.text('社区组织数量'), findsOneWidget);
      expect(find.text('舰队数量'), findsNothing);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('累计游戏时长'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'feedback is explicit, single flight, and retains text after an uncertain send',
    (tester) async {
      final port = _SupportFake();
      final contact = TextEditingController(),
          message = TextEditingController();
      addTearDown(contact.dispose);
      addTearDown(message.dispose);
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: HelpSupportFeedbackForm(
              port: port,
              contact: contact,
              message: message,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(port.sends, 0);
      await tester.enterText(
        find.byKey(const Key('help-feedback-message')),
        'Synthetic feedback',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('help-feedback-send')));
      await tester.tap(find.byKey(const Key('help-feedback-send')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('help-feedback-send')))
            .onPressed,
        isNull,
      );
      expect(port.sends, 1);
      port.pending.completeError(StateError('synthetic failure'));
      await tester.pumpAndSettle();
      expect(message.text, 'Synthetic feedback');
      expect(find.textContaining('内容已保留'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(port.sends, 1);
    },
  );
  testWidgets('shows the four help topics and the complete log catalog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const HelpSupportSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-help-support-page')), findsOneWidget);
    for (final topic in HelpSupportTopic.values) {
      expect(
        find.byKey(Key('help-topic-button-${topic.name}')),
        findsOneWidget,
      );
    }
    for (var index = 0; index < 10; index++) {
      expect(find.byKey(Key('help-log-category-$index')), findsOneWidget);
    }
    expect(find.byKey(const Key('help-log-category-10')), findsNothing);
    expect(find.textContaining('不会自动上传地点代码'), findsNothing);

    await tester.tap(find.byKey(const Key('help-log-category-4')));
    await tester.pumpAndSettle();
    expect(find.textContaining('不会自动上传地点代码'), findsOneWidget);
  });

  testWidgets('keeps legal notices and fankit attribution together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const HelpSupportSettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help-topic-button-notices')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('help-topic-notices')), findsOneWidget);
    expect(find.byKey(const Key('help-cig-fankit-notice')), findsOneWidget);
    expect(find.byKey(const Key('help-third-party-licenses')), findsOneWidget);
    expect(find.text('非官方说明'), findsOneWidget);
  });

  testWidgets('says how the in-game menu takes focus', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const HelpSupportSettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help-topic-button-notices')));
    await tester.pumpAndSettle();
    final section = find.text('游戏安全与信息准确性');
    await tester.ensureVisible(section);
    await tester.tap(section);
    await tester.pumpAndSettle();

    expect(find.textContaining('是否符合 RSI 条款由 CIG 判断'), findsOneWidget);
    for (final strings in [helpSupportZhCn, helpSupportZhTw, helpSupportEnUs]) {
      final body = strings['help.legal.safety.body']!;
      expect(body, contains('Alt+M'));
      expect(body, contains('AttachThreadInput'));
    }
    expect(helpSupportZhCn['help.legal.safety.body'], contains('程序路径'));
    expect(helpSupportZhTw['help.legal.safety.body'], contains('程式路徑'));
    expect(helpSupportEnUs['help.legal.safety.body'], contains('program path'));
  });

  testWidgets(
    'opens bundled dependency and font licenses without a network action',
    (tester) async {
      // This isolated page bypasses bootstrap; mirror its license registration.
      LicenseRegistry.reset();
      StarBridgeThirdPartyLicenses.registerAtStartup();
      addTearDown(LicenseRegistry.reset);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(const HelpSupportSettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('help-topic-button-notices')));
      await tester.pumpAndSettle();
      final action = find.byKey(const Key('help-open-third-party-licenses'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.byType(ThirdPartyLicenseBrowser), findsOneWidget);
      expect(find.text('Source Sans 3'), findsWidgets);
    },
  );

  testWidgets('does not present an unconnected update action as working', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const HelpSupportSettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help-topic-button-updates')));
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('help-check-updates')),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('暂时无法读取，请重试。'), findsWidgets);
  });

  testWidgets('copies the real feedback group number', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(_app(const HelpSupportSettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help-topic-button-feedback')));
    await tester.pumpAndSettle();
    final copyButton = find.byKey(const Key('help-copy-feedback-group'));
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pump();

    expect(clipboardText, '534268220');
    expect(find.text('星海舰桥反馈群号已复制。'), findsOneWidget);
  });

  // User 11-16: two QQ groups and an email, each copied on tap.
  testWidgets('feedback lists both QQ groups and the email, each copyable', (
    tester,
  ) async {
    final copied = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text'] as String?,
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(_app(const HelpSupportSettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help-topic-button-feedback')));
    await tester.pumpAndSettle();
    expect(find.text('SCM 星海舰桥反馈群'), findsOneWidget);
    expect(find.text('SCM 团队 QQ 反馈群'), findsOneWidget);
    expect(find.textContaining('如果希望加入我们，也请进入此群'), findsOneWidget);
    expect(find.text('邮箱：scstarbridge.app@gmail.com'), findsOneWidget);
    for (final (key, value, notice) in [
      ('help-copy-feedback-team-group', '588620092', 'SCM 团队群号已复制。'),
      ('help-copy-feedback-email', 'scstarbridge.app@gmail.com', '邮箱地址已复制。'),
    ]) {
      final button = find.byKey(Key(key));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(copied.last, value);
      expect(find.text(notice), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  // User 11-16: "反馈群第一个用星海舰桥logo 中间用scmlogo". Email keeps its
  // glyph; the SCM artwork is tinted only on the light theme.
  for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
    testWidgets('feedback cards show StarBridge, SCM, then email marks ($mode)', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const HelpSupportSettingsPage(), mode: mode));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('help-topic-button-feedback')));
      await tester.pumpAndSettle();
      final light = mode == AppearanceMode.light;

      final group = find.byKey(const Key('help-feedback-mark-group'));
      expect(
        find.descendant(of: group, matching: find.byType(StarBridgeAppIcon)),
        findsOneWidget,
      );
      expect(tester.getSize(group), const Size(26, 26));

      final team = find.byKey(const Key('help-feedback-mark-team-group'));
      final scm = tester.widget<Image>(
        find.descendant(of: team, matching: find.byType(Image)),
      );
      expect((scm.image as AssetImage).assetName, ScmBrandMark.markAssetPath);
      expect(scm.color != null, light);
      expect(scm.colorBlendMode, light ? BlendMode.srcIn : null);
      expect(tester.getSize(team), const Size(26, 26));

      final email = find.byKey(const Key('help-feedback-mark-email'));
      expect(
        find.descendant(of: email, matching: find.byType(StarBridgeIcon)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: email, matching: find.byType(Image)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // User 11-16: StarBridge icon opens our website, GitHub icon our repository.
  testWidgets('StarBridge and GitHub icons open their pages only on click', (
    tester,
  ) async {
    final port = _LinkFake();
    await tester.pumpWidget(_app(HelpSupportSettingsPage(port: port)));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('GitHub'), findsOneWidget);
    expect(port.names, isEmpty);
    await tester.tap(find.byKey(const Key('help-starbridge-website')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help-github')));
    await tester.pumpAndSettle();
    expect(port.names, ['helpSupport.openWebsite', 'helpSupport.openGitHub']);
    expect(find.textContaining('未能打开浏览器'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (key, host) in [
    ('help-starbridge-website', 'scstarbridge.com'),
    ('help-github', 'github.com/Domino-L/StarBridge-OpenCore'),
  ]) {
    testWidgets('$key tells where to go when the browser does not open', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(HelpSupportSettingsPage(port: _LinkFake()..fail = true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
      expect(find.text('未能打开浏览器，可手动访问 $host。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('uses the compact topic picker without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(const HelpSupportSettingsPage()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('help-topic-button-feedback')), findsOneWidget);
  });

  testWidgets('opens from the production settings navigation', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        SettingsPage(
          initialSection: SettingsSection.generalData,
          accountAndIdentityBuilder: (_) => const Text('account'),
          generalDataBuilder: (_) => const Text('general'),
          syncPrivacyBuilder: (_) => const Text('privacy'),
          notificationsBuilder: (_) => const Text('notifications'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-section-aboutLegal')));
    await tester.pumpAndSettle();

    expect(find.text('帮助与支持'), findsWidgets);
    expect(find.byKey(const Key('settings-help-support-page')), findsOneWidget);
  });

  test('help copy exists in every supported locale', () {
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      for (final key in helpSupportZhCn.keys) {
        expect(
          strings.text(key),
          isNot(key),
          reason: '$locale is missing $key',
        );
      }
    }
  });
}

class _ScmLinkFake implements HelpSupportPort {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> read(String name) async {
    expect(name, 'helpSupport.openScm');
    calls++;
    return {'schemaVersion': 1, 'opened': true};
  }

  @override
  Future<void> send(String contact, String message) async {}
}

class _LinkFake implements HelpSupportPort {
  final names = <String>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> read(String name) async {
    names.add(name);
    if (fail) throw StateError('Support unavailable');
    return {'schemaVersion': 1, 'opened': true};
  }

  @override
  Future<void> send(String contact, String message) async {}
}

class _SupportFake implements HelpSupportPort {
  List<dynamic>? historyEntries;
  Object? accountCount;
  Object? scmUserCount;
  int sends = 0;
  final pending = Completer<void>();
  @override
  Future<void> send(String contact, String message) {
    sends++;
    return pending.future;
  }

  @override
  Future<Map<String, dynamic>> read(String name) async => switch (name) {
    'applicationUpdates.check' => {
      'schemaVersion': 1,
      'state': 'channel-unconfigured',
      'currentVersion': '0.1.0+1',
      'availableVersion': null,
      'notes': null,
    },
    'helpSupport.history' => {
      'schemaVersion': 1,
      'edition': 'starbridge',
      'entries':
          historyEntries ??
          [
            {
              'version': '0.6.6',
              'publishedOn': '2026-08-18',
              'title': 'Synthetic release',
              'summary': 'Summary',
              'highlights': ['One change'],
            },
          ],
    },
    _ => {
      'schemaVersion': 1,
      if (accountCount != null) 'registeredAccountCount': accountCount,
      if (scmUserCount != null) 'scmUserCount': scmUserCount,
      'downloadCount': 5,
      'onlineUserCount': 2,
      'fleetCount': 3,
      'overlayUsageSeconds': 3600,
      'updatedAt': '2026-09-15T12:00:00Z',
    },
  };
}

Widget _app(
  Widget home, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
}) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, mode)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(body: home),
  );
}
