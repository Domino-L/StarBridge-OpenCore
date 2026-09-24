import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_avatar_actions.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

void main() {
  testWidgets(
    'avatar menu requires an explicit profile click and retires with target',
    (tester) async {
      var clicks = 0;
      Widget subject(String key, {bool enabled = true}) => MaterialApp(
        home: Scaffold(
          body: MenuAvatarActions(
            key: ValueKey(key),
            name: 'Fixture pilot',
            onProfile: enabled ? () => clicks++ : null,
            child: const SizedBox(width: 40, height: 40, child: Text('头像')),
          ),
        ),
      );
      await tester.pumpWidget(subject('first'));
      await tester.tap(find.text('头像'));
      await tester.pumpAndSettle();
      expect(clicks, 0);
      expect(find.text('查看个人页面'), findsOneWidget);
      await tester.tap(find.text('查看个人页面'));
      await tester.pumpAndSettle();
      expect(clicks, 1);
      await tester.tap(find.text('头像'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(subject('next', enabled: false));
      await tester.pumpAndSettle();
      expect(find.text('查看个人页面'), findsNothing);
      expect(clicks, 1);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets('real history respects compact layout and text scale $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(960, 720);
      addTearDown(tester.view.reset);
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('zh', 'CN'),
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(960, 720),
              textScaler: TextScaler.linear(scale),
            ),
            child: MenuBridgePreview(
              visible: true,
              onDismiss: () {},
              friends: const MenuFriendsView('idle'),
              comms: MenuCommsView(
                'ready',
                name: '测试会话名称',
                hasOlder: true,
                messages: [
                  (
                    incoming: true,
                    text: '较长的消息内容' * 80,
                    time: DateTime(2026),
                    attachment: true,
                  ),
                ],
              ),
              onCommsAction: (action, key) => actions.add(action),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-tool-chat')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      expect(find.text('测试会话名称'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('menu-comms-older')),
      );
      await tester.tap(find.byKey(const ValueKey('menu-comms-older')));
      expect(actions, ['older']);
      expect(find.text('此附件类型暂不支持在菜单内操作。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('avatars never fetch URLs and clear invalid replacements', (
    tester,
  ) async {
    const png =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aO0cAAAAASUVORK5CYII=';
    Widget avatar(String? source) =>
        MaterialApp(home: MenuInlineAvatar(source: source));
    await tester.pumpWidget(avatar(png));
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(avatar('https://invalid.test/avatar'));
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(avatar('data:image/png;base64,%%%'));
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(avatar(null));
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
