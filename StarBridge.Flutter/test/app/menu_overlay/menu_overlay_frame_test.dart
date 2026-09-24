import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_frame.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

MenuOverlayTool tool(String id, {VoidCallback? action}) => MenuOverlayTool(
  id: id,
  label: '工具 $id',
  icon: StarBridgeIconSemantic.tools,
  onActivate: action ?? () {},
);

MenuOverlayFrame frame({
  Iterable<MenuOverlayTool> tools = const [],
  VoidCallback? onReturn,
  VoidCallback? onSettings,
}) => MenuOverlayFrame(
  contextLabel: '当前组织 / 当前房间 · 这是较长的上下文名称',
  clockLabel: '20:35',
  returnLabel: '返回游戏',
  settingsLabel: '菜单设置',
  onReturn: onReturn ?? () {},
  onSettings: onSettings,
  tools: tools,
  workspace: const Center(child: Text('workspace slot')),
);

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('zh'),
      ),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    ),
  );
}

void main() {
  test('copies registrations and rejects duplicate or blank IDs', () {
    final source = [tool('friends')];
    final result = frame(tools: source);
    source.clear();
    expect(result.tools.single.id, 'friends');
    expect(() => result.tools.clear(), throwsUnsupportedError);
    expect(
      () => frame(tools: [tool('same'), tool('same')]),
      throwsArgumentError,
    );
    expect(() => frame(tools: [tool(' ')]), throwsArgumentError);
  });

  for (final size in [
    const Size(2560, 1440),
    const Size(1280, 720),
    const Size(640, 480),
    const Size(320, 360),
  ]) {
    testWidgets('frame fits $size at 200 percent text', (tester) async {
      tester.view.reset();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await mount(
        tester,
        frame(
          tools: List.generate(12, (i) => tool('tool-$i')),
          onSettings: () {},
        ),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('workspace slot'), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-return')), findsOneWidget);
      if (size.width < 1000) {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('menu-tool-tool-11')),
          200,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('menu-dock')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('menu-tool-tool-11')).hitTestable(),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('actions are explicit; unavailable tools do not execute', (
    tester,
  ) async {
    final calls = <String>[];
    await mount(
      tester,
      frame(
        onReturn: () => calls.add('return'),
        onSettings: () => calls.add('settings'),
        tools: [
          tool('friends', action: () => calls.add('friends')),
          const MenuOverlayTool(
            id: 'future',
            label: '未来功能',
            icon: StarBridgeIconSemantic.tools,
            unavailableReason: '尚未接入',
          ),
        ],
      ),
    );
    expect(calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('menu-tool-future')));
    expect(calls, isEmpty);
    expect(find.byTooltip('尚未接入'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
    await tester.tap(find.byTooltip('菜单设置'));
    await tester.tap(find.byKey(const ValueKey('menu-return')));
    expect(calls, ['friends', 'settings', 'return']);
  });

  testWidgets('open, active and unread indicators are independent', (
    tester,
  ) async {
    await mount(
      tester,
      frame(
        tools: [
          MenuOverlayTool(
            id: 'friends',
            label: '好友',
            icon: StarBridgeIconSemantic.friends,
            onActivate: () {},
            isOpen: true,
            isActive: true,
          ),
          MenuOverlayTool(
            id: 'room',
            label: '房间',
            icon: StarBridgeIconSemantic.room,
            onActivate: () {},
            hasUnread: true,
          ),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('menu-open-friends')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-open-room')), findsNothing);
    expect(
      tester
          .widget<Badge>(find.byKey(const ValueKey('menu-unread-friends')))
          .isLabelVisible,
      isFalse,
    );
    expect(
      tester
          .widget<Badge>(find.byKey(const ValueKey('menu-unread-room')))
          .isLabelVisible,
      isTrue,
    );
  });

  testWidgets('empty registry shows no phantom dock or settings action', (
    tester,
  ) async {
    await mount(tester, frame());
    expect(find.byKey(const ValueKey('menu-dock')), findsNothing);
    expect(find.byTooltip('菜单设置'), findsNothing);
    expect(find.text('workspace slot'), findsOneWidget);
  });
}
