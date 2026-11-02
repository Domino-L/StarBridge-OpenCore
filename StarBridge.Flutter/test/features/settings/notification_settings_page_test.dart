import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/notification_settings_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/host_unavailable_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/in_memory_notification_settings_adapter.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_module.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_page.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_channels.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_comparison.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'desktop child retains its preference when master is off at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var value =
            InMemoryNotificationSettingsAdapter.forReview().current.settings!;
        value = value.copyWith(
          channels: value.channels.copyWith(directMessageWindowsEnabled: true),
        );
        await tester.pumpWidget(
          _app(
            StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: NotificationChannelPanel(
                  settings: value,
                  enabled: true,
                  onSave: (next) async {
                    setState(() => value = next);
                    return true;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final master = find.byKey(const Key('notification-channel-windows'));
        final child = find.byKey(
          const Key('notification-channel-direct-message'),
        );
        expect(
          tester.getTopLeft(child).dx,
          greaterThan(tester.getTopLeft(master).dx - 1),
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('notification-desktop-child')),
            matching: child,
          ),
          findsOneWidget,
        );
        await tester.tap(master);
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(child).onChanged, isNull);
        expect(tester.widget<Switch>(child).value, isTrue);
        await tester.tap(master);
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(child).onChanged, isNotNull);
        expect(tester.widget<Switch>(child).value, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('trade alerts sit under Windows, default on, follow the master', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var value =
        InMemoryNotificationSettingsAdapter.forReview().current.settings!;
    value = value.copyWith(
      channels: value.channels.copyWith(windowsDesktopEnabled: true),
    );
    expect(value.channels.tradeWindowsEnabled, isTrue);
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: NotificationChannelPanel(
              settings: value,
              enabled: true,
              onSave: (next) async {
                setState(() => value = next);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final master = find.byKey(const Key('notification-channel-windows'));
    final trade = find.byKey(const Key('notification-channel-trade'));
    expect(
      find.descendant(
        of: find.byKey(const Key('notification-desktop-child')),
        matching: trade,
      ),
      findsOneWidget,
    );
    expect(find.text('交易提醒'), findsOneWidget);
    expect(find.text('默认开启'), findsOneWidget);
    expect(
      tester.getTopLeft(trade).dy,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(const Key('notification-channel-direct-message')),
            )
            .dy,
      ),
    );
    expect(tester.widget<Switch>(trade).value, isTrue);
    await tester.tap(trade);
    await tester.pumpAndSettle();
    expect(value.channels.tradeWindowsEnabled, isFalse);
    await tester.tap(trade);
    await tester.pumpAndSettle();
    await tester.tap(master);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(trade).onChanged, isNull);
    expect(tester.widget<Switch>(trade).value, isTrue);
    expect(tester.takeException(), isNull);
  });
  for (final (dm, trade) in [(true, false), (false, true), (false, false)]) {
    testWidgets('local mode shows only available child rows: dm=$dm trade=$trade', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final review =
          InMemoryNotificationSettingsAdapter.forReview().current.settings!;
      final value = NotificationSettingsValue(
        localInAppOnly: true,
        desktopDeliveryAvailable: true,
        directMessageDeliveryAvailable: dm,
        tradeDeliveryAvailable: trade,
        channels: review.channels,
        sourceRules: review.sourceRules,
        previewMode: review.previewMode,
        playerActivity: review.playerActivity,
        continuousPlay: review.continuousPlay,
      );
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: NotificationChannelPanel(
              settings: value,
              enabled: true,
              onSave: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('notification-channel-direct-message')),
        dm ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('notification-channel-trade')),
        trade ? findsOneWidget : findsNothing,
      );
      // No empty child container when neither row is available.
      expect(
        find.byKey(const Key('notification-desktop-child')),
        dm || trade ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('trade alerts keep an off choice across the master and touch nothing else', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var value =
        InMemoryNotificationSettingsAdapter.forReview().current.settings!;
    value = value.copyWith(
      channels: value.channels.copyWith(windowsDesktopEnabled: true),
    );
    final before = value;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: NotificationChannelPanel(
              settings: value,
              enabled: true,
              onSave: (next) async {
                setState(() => value = next);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final master = find.byKey(const Key('notification-channel-windows'));
    final trade = find.byKey(const Key('notification-channel-trade'));
    await tester.tap(trade);
    await tester.pumpAndSettle();
    expect(
      sameNotificationSettings(
        value,
        before.copyWith(
          channels: before.channels.copyWith(tradeWindowsEnabled: false),
        ),
      ),
      isTrue,
      reason: 'only the trade field changes',
    );
    await tester.tap(master);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(trade).value, isFalse);
    await tester.tap(master);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(trade).onChanged, isNotNull);
    expect(tester.widget<Switch>(trade).value, isFalse);
    expect(value.channels.tradeWindowsEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Windows switch is marked recommended only while off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var value =
        InMemoryNotificationSettingsAdapter.forReview().current.settings!;
    value = value.copyWith(
      channels: value.channels.copyWith(windowsDesktopEnabled: false),
    );
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: NotificationChannelPanel(
              settings: value,
              enabled: true,
              onSave: (next) async {
                setState(() => value = next);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final badge = find.byKey(const Key('notification-recommended'));
    expect(badge, findsOneWidget);
    expect(find.text('推荐开启'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notification-channel-windows')));
    await tester.pumpAndSettle();
    expect(value.channels.windowsDesktopEnabled, isTrue);
    expect(badge, findsNothing);
  });
  testWidgets('renders a user-facing notification workspace and test alert', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = InMemoryNotificationSettingsAdapter.forReview();
    final module = createNotificationSettingsModule(adapter);
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(NotificationSettingsPage(module: module)));
    await tester.pumpAndSettle();

    expect(find.text('通知与提醒'), findsOneWidget);
    expect(find.byKey(const Key('notification-delivery-logic')), findsNothing);
    expect(find.textContaining('Native Host'), findsNothing);
    expect(find.textContaining('eventId'), findsNothing);
    expect(find.textContaining('WPF'), findsNothing);
    expect(find.byKey(const Key('notification-channel-panel')), findsOneWidget);
    expect(
      find.byKey(const Key('notification-source-rules-panel')),
      findsOneWidget,
    );
    expect(find.textContaining('单独设置免打扰'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('notification-channel-windows')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Switch>(
            find.byKey(const Key('notification-channel-direct-message')),
          )
          .value,
      isFalse,
    );
    expect(find.byKey(const Key('notification-channel-sound')), findsNothing);
    expect(find.text('暂不可用'), findsOneWidget);

    final testButton = find.byKey(const Key('notification-test-button'));
    await tester.ensureVisible(testButton);
    await tester.tap(testButton);
    await tester.pump();

    expect(
      find.byKey(const Key('starbridge-notification-toast')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('starbridge-notification-toast')),
        matching: find.text('有新的房间消息，请前往房间查看。'),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final hiddenPreview = find.byKey(
      const Key('notification-preview-hiddenDetails'),
    );
    await tester.ensureVisible(hiddenPreview);
    await tester.tap(hiddenPreview);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('notification-preview-example')),
        matching: find.text('你有新的通知，请打开通知页查看。'),
      ),
      findsOneWidget,
    );
    expect(
      adapter.current.settings!.previewMode,
      NotificationPreviewMode.sourceOnly,
    );

    final sourceSelector = find.byKey(
      const Key('notification-source-mode-official-fleet:aster'),
    );
    await tester.ensureVisible(sourceSelector);
    await tester.pumpAndSettle();
    final important = find.descendant(
      of: sourceSelector,
      matching: find.text('仅关键变化'),
    );
    await tester.tap(important);
    await tester.pumpAndSettle();

    expect(adapter.current.revision, 11);
    await tester.tap(find.byKey(const Key('notification-save')));
    await tester.pumpAndSettle();
    expect(adapter.current.revision, 12);
    expect(
      adapter.current.settings!.previewMode,
      NotificationPreviewMode.hiddenDetails,
    );

    expect(
      adapter.current.settings!.sourceRules.first.mode,
      NotificationSourceMode.importantOnly,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps player activity events and play intervals visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = InMemoryNotificationSettingsAdapter.forReview();
    final module = createNotificationSettingsModule(adapter);
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(NotificationSettingsPage(module: module)));
    await tester.pumpAndSettle();

    for (final key in <Key>[
      const Key('notification-activity-online'),
      const Key('notification-activity-offline'),
      const Key('notification-activity-game-start'),
      const Key('notification-activity-game-stop'),
      const Key('notification-play-enabled'),
      const Key('notification-play-first'),
      const Key('notification-play-repeat'),
    ]) {
      final finder = find.byKey(key);
      await tester.scrollUntilVisible(finder, 420);
      expect(finder, findsOneWidget);
    }
    expect(find.textContaining('地点代码'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product-unavailable state exposes no simulated controls', (
    tester,
  ) async {
    final module = createNotificationSettingsModule(
      HostUnavailableNotificationSettingsAdapter(),
    );
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(NotificationSettingsPage(module: module)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('notification-settings-unavailable')),
      findsOneWidget,
    );
    expect(find.textContaining('通知服务暂时不可用'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(SegmentedButton<NotificationSourceMode>), findsNothing);
  });

  test('notification page copy exists in every supported locale', () {
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      for (final key in <String>[
        'settings.notification.title',
        'settings.notification.channels.title',
        'settings.notification.test.action',
        'settings.notification.test.title',
        'settings.notification.test.body',
        'settings.notification.sources.title',
        'settings.notification.preview.title',
        'settings.notification.activity.title',
        'settings.notification.play.title',
        'settings.notification.error.hostUnavailable',
      ]) {
        expect(strings.text(key), isNot(key));
      }
    }
    expect(
      traditionalNotificationSettingsStrings.keys.toSet(),
      simplifiedNotificationSettingsStrings.keys.toSet(),
    );
    expect(
      englishNotificationSettingsStrings.keys.toSet(),
      simplifiedNotificationSettingsStrings.keys.toSet(),
    );
  });

  test('notification copy avoids internal implementation terminology', () {
    for (final copy in <Map<String, String>>[
      simplifiedNotificationSettingsStrings,
      traditionalNotificationSettingsStrings,
      englishNotificationSettingsStrings,
    ]) {
      final visibleCopy = copy.values.join('\n');
      expect(visibleCopy, isNot(contains('Native Host')));
      expect(visibleCopy, isNot(contains('eventId')));
      expect(visibleCopy, isNot(contains('WPF')));
      expect(visibleCopy, isNot(contains('模拟开关')));
      expect(visibleCopy, isNot(contains('simulated controls')));
    }
  });
}

Widget _app(Widget home) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
    home: Scaffold(body: home),
  );
}
