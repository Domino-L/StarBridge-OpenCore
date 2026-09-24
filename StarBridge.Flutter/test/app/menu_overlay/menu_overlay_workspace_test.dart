import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, capture, loadFonts;

class Probe {
  int builds = 0;
  int mounted = 0;
  int disposed = 0;
}

class ProbeBody extends StatefulWidget {
  const ProbeBody(this.id, this.probe, {super.key});
  final String id;
  final Probe probe;
  @override
  State<ProbeBody> createState() => _ProbeBodyState();
}

class _ProbeBodyState extends State<ProbeBody> {
  final text = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.probe.mounted++;
  }

  @override
  void dispose() {
    widget.probe.disposed++;
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.probe.builds++;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Text('面板内容 · ${widget.id}'),
          TextField(key: ValueKey('input-${widget.id}'), controller: text),
        ],
      ),
    );
  }
}

class Fixture {
  final probes = {'friends': Probe(), 'chat': Probe()};
  final specs = [
    MenuPanelSpec(
      id: 'friends',
      initialBounds: const Rect.fromLTWH(20, 30, 320, 260),
    ),
    MenuPanelSpec(
      id: 'chat',
      initialBounds: const Rect.fromLTWH(420, 30, 400, 260),
    ),
  ];
  late final controller = MenuWorkspaceController(
    scope: 'fixture',
    panels: specs,
  );
  late final panels = [
    for (final id in probes.keys)
      MenuPanelContent(
        id: id,
        title: id == 'friends' ? '好友' : '消息',
        icon: StarBridgeIconSemantic.tools,
        builder: (_, lease) => ProbeBody(lease.id, probes[lease.id]!),
      ),
  ];
  Widget view({double scale = 1}) => app(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MenuOverlayWorkbench(
        controller: controller,
        panels: panels,
        contextLabel: '工作区 · 组件验证',
        returnLabel: '返回游戏',
        settingsLabel: '菜单设置',
        closeLabel: '关闭面板',
        moveLabel: '移动面板',
        resizeLabel: '调整大小',
        onReturn: () => controller.setVisible(false),
      ),
    ),
  );
}

Finder keyed(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets(
    'dock opens once, preserves body when raised and closes explicitly',
    (tester) async {
      size(tester, const Size(1280, 720));
      final f = Fixture();
      await tester.pumpWidget(f.view());
      await tester.pumpAndSettle();
      await tester.tap(keyed('menu-tool-friends'));
      await tester.pumpAndSettle();
      await tester.enterText(keyed('input-friends'), '草稿保留');
      await tester.tap(keyed('menu-tool-chat'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('menu-tool-friends'));
      await tester.pumpAndSettle();
      expect(f.controller.openPanels.length, 2);
      expect(f.controller.activeId, 'friends');
      expect(f.probes['friends']!.mounted, 1);
      expect(find.text('草稿保留'), findsOneWidget);
      await tester.tap(keyed('menu-close-friends'));
      await tester.pumpAndSettle();
      expect(f.controller.activeId, 'chat');
      expect(f.probes['friends']!.disposed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('drag and resize move chrome without rebuilding body', (
    tester,
  ) async {
    size(tester, const Size(1280, 720));
    final f = Fixture();
    f.controller.open('friends');
    await tester.pumpWidget(f.view());
    await tester.pumpAndSettle();
    final before = tester.getRect(keyed('menu-panel-friends'));
    final builds = f.probes['friends']!.builds;
    await tester.drag(keyed('menu-move-friends'), const Offset(100, 60));
    await tester.pumpAndSettle();
    final moved = tester.getRect(keyed('menu-panel-friends'));
    expect(moved.left, greaterThan(before.left + 50));
    expect(moved.top, greaterThan(before.top + 20));
    await tester.drag(keyed('menu-resize-friends'), const Offset(80, 60));
    await tester.pumpAndSettle();
    final resized = tester.getRect(keyed('menu-panel-friends'));
    expect(resized.width, greaterThan(moved.width + 30));
    expect(resized.height, greaterThan(moved.height + 20));
    expect(resized.topLeft, moved.topLeft);
    expect(f.probes['friends']!.builds, builds);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard handles move and resize in predictable steps', (
    tester,
  ) async {
    size(tester, const Size(1280, 720));
    final f = Fixture();
    f.controller.open('friends');
    await tester.pumpWidget(f.view());
    await tester.pumpAndSettle();
    Future<void> focusHandle(String id) async {
      final button = find.descendant(
        of: keyed(id),
        matching: find.byType(TextButton),
      );
      Focus.of(
        tester.element(
          find.descendant(of: button, matching: find.byType(Align)).first,
        ),
      ).requestFocus();
      await tester.pump();
    }

    final initial = tester.getRect(keyed('menu-panel-friends'));
    await focusHandle('menu-move-friends');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.getRect(keyed('menu-panel-friends')).left, initial.left + 10);
    await focusHandle('menu-resize-friends');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester.getRect(keyed('menu-panel-friends')).height,
      initial.height + 10,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small desktop preserves every window and its draft and placement',
    (tester) async {
      size(tester, const Size(1280, 720));
      final f = Fixture();
      f.controller.open('friends');
      await tester.pumpWidget(f.view(scale: 2));
      await tester.pumpAndSettle();
      await tester.enterText(keyed('input-friends'), '保留输入');
      final wide = tester.getRect(keyed('menu-panel-friends'));
      f.controller.open('chat');
      tester.view.physicalSize = const Size(640, 480);
      await tester.pumpAndSettle();
      expect(keyed('menu-panel-friends'), findsOneWidget);
      expect(keyed('menu-panel-chat'), findsOneWidget);
      expect(keyed('menu-resize-chat'), findsOneWidget);
      f.controller.activate('friends');
      await tester.pumpAndSettle();
      expect(find.text('保留输入'), findsOneWidget);
      expect(f.probes['friends']!.mounted, 1);
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();
      expect(tester.getRect(keyed('menu-panel-friends')), wide);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden content pauses ticker and focus; revocation disposes it',
    (tester) async {
      size(tester, const Size(1280, 720));
      final f = Fixture();
      f.controller.open('friends');
      await tester.pumpWidget(f.view());
      await tester.pumpAndSettle();
      await tester.enterText(keyed('input-friends'), '保留');
      f.controller.setVisible(false);
      await tester.pumpAndSettle();
      expect(keyed('menu-panel-friends'), findsNothing);
      final hidden = find.byKey(
        const ValueKey('input-friends'),
        skipOffstage: false,
      );
      expect(TickerMode.valuesOf(tester.element(hidden)).enabled, false);
      expect(FocusScope.of(tester.element(hidden)).hasFocus, false);
      expect(f.probes['friends']!.disposed, 0);
      f.controller.setVisible(true);
      await tester.pumpAndSettle();
      expect(find.text('保留'), findsOneWidget);
      f.controller.reconcile(scope: 'fixture', panels: [f.specs.last]);
      await tester.pumpAndSettle();
      expect(f.probes['friends']!.disposed, 1);
      expect(keyed('menu-tool-friends'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scope change disposes previous content; preview uses synthetic data only',
    (tester) async {
      size(tester, const Size(1280, 720));
      final f = Fixture();
      f.controller.open('friends');
      f.controller.open('chat');
      final boundary = GlobalKey();
      await tester.runAsync(loadFonts);
      await tester.runAsync(() async {
        await (FontLoader('Source Code Pro')..addFont(
              rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf'),
            ))
            .load();
      });
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: f.view()));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('工作区 · 组件验证')).style!.fontFamilyFallback,
        contains('Source Han Sans CN'),
      );
      await capture(tester, boundary, 'menu-workspace-m3');
      tester.view.physicalSize = const Size(640, 480);
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'menu-workspace-m3-compact');
      f.controller.reconcile(scope: 'another-context', panels: f.specs);
      await tester.pumpAndSettle();
      expect(f.probes.values.every((p) => p.disposed == 1), true);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
