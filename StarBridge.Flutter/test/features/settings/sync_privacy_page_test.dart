import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/host_unavailable_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_page.dart';

void main() {
  testWidgets('renders audience-first privacy controls and persists edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = InMemorySyncPrivacyAdapter.forReview();
    final module = createSyncPrivacyModule(adapter);
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(SyncPrivacyPage(module: module)));
    await tester.pumpAndSettle();

    expect(find.text('决定谁能看到什么'), findsOneWidget);
    expect(find.byKey(const Key('privacy-visibility-map')), findsOneWidget);
    expect(find.text('好友'), findsOneWidget);
    expect(find.text('当前房间或行动'), findsOneWidget);
    expect(find.text('舰队、组织与其他玩家'), findsOneWidget);
    expect(find.textContaining('地点代码'), findsNothing);

    final ship = find.byKey(const Key('privacy-friends-ship'));
    await tester.ensureVisible(ship);
    await tester.pumpAndSettle();
    await tester.tap(ship);
    await tester.pumpAndSettle();

    expect(adapter.current.settings!.friendDefaults.ship, isTrue);

    final strangerMessages = find.text('允许非好友发起私信');
    await tester.ensureVisible(strangerMessages);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy-stranger-messages')), findsNothing);
    expect(find.text('暂时无法读取私信接收设置。'), findsOneWidget);
    expect(find.text('舰船共享在个人机库管理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pausing realtime sync confirms active collaboration impact', (
    tester,
  ) async {
    final adapter = InMemorySyncPrivacyAdapter.forReview();
    final module = createSyncPrivacyModule(adapter);
    addTearDown(module.dispose);
    await module.initialize();
    await tester.pumpWidget(_app(SyncPrivacyPage(module: module)));
    await tester.pumpAndSettle();

    final realtime = find.byKey(const Key('privacy-realtime-sync'));
    await tester.ensureVisible(realtime);
    await tester.pumpAndSettle();
    await tester.tap(realtime);
    await tester.pumpAndSettle();

    expect(find.text('暂停实时同步？'), findsOneWidget);
    expect(find.textContaining('行动参与与舰船占用不会自动解除'), findsOneWidget);
    await tester.tap(find.text('暂停实时同步').last);
    await tester.pumpAndSettle();

    expect(adapter.current.settings!.realtimeSyncEnabled, isFalse);
  });

  testWidgets('product-unavailable state exposes no simulated controls', (
    tester,
  ) async {
    final module = createSyncPrivacyModule(HostUnavailableSyncPrivacyAdapter());
    addTearDown(module.dispose);
    await module.initialize();
    await tester.pumpWidget(_app(SyncPrivacyPage(module: module)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync-privacy-unavailable')), findsOneWidget);
    expect(find.textContaining('没有显示或保存任何模拟开关'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  test('privacy page copy exists in every supported locale', () {
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      for (final key in <String>[
        'settings.privacy.title',
        'settings.privacy.map.title',
        'settings.privacy.friends.title',
        'settings.privacy.events.title',
        'settings.privacy.social.title',
        'settings.privacy.hangar.title',
        'settings.privacy.error.hostUnavailable',
      ]) {
        expect(strings.text(key), isNot(key));
      }
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
