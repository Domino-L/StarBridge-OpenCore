// build 72 acceptance: a menu panel lying over another one stays opaque.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_panel_idle.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';

import '../../features/friends/social_layout_test.dart' show app, size;

double _opacity(WidgetTester tester, String id) => tester
    .widget<Opacity>(
      find.ancestor(
        of: find.byKey(ValueKey('content-$id')),
        matching: find.byKey(const ValueKey('menu-panel-idle-opacity')),
      ),
    )
    .opacity;

Future<MenuWorkspaceController> _pump(
  WidgetTester tester, {
  required Rect back,
  required Rect front,
}) async {
  size(tester, const Size(1280, 720));
  final workspace = MenuWorkspaceController(
    scope: Object(),
    panels: [
      MenuPanelSpec(id: 'back', initialBounds: back),
      MenuPanelSpec(id: 'front', initialBounds: front),
    ],
  );
  addTearDown(workspace.dispose);
  workspace.open('back');
  workspace.open('front');
  await tester.pumpWidget(
    app(
      MenuOverlayWorkspace(
        controller: workspace,
        panels: [
          for (final id in ['back', 'front'])
            MenuPanelContent(
              id: id,
              title: id,
              icon: StarBridgeIconSemantic.tools,
              builder: (_, _) => SizedBox.expand(key: ValueKey('content-$id')),
            ),
        ],
        closeLabel: 'Close',
        moveLabel: 'Move',
        resizeLabel: 'Resize',
        bridgeStyle: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Idle long enough for the fade to finish.
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 300));
  return workspace;
}

void main() {
  testWidgets('the panel on top of another stays opaque while idle', (
    tester,
  ) async {
    await _pump(
      tester,
      back: const Rect.fromLTWH(50, 50, 400, 300),
      front: const Rect.fromLTWH(150, 100, 400, 300),
    );
    expect(_opacity(tester, 'front'), 1);
    expect(_opacity(tester, 'back'), .7, reason: 'the covered one still fades');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bringing the lower panel up swaps which one stays opaque', (
    tester,
  ) async {
    final workspace = await _pump(
      tester,
      back: const Rect.fromLTWH(50, 50, 400, 300),
      front: const Rect.fromLTWH(150, 100, 400, 300),
    );
    workspace.activate('back');
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_opacity(tester, 'back'), 1);
    expect(_opacity(tester, 'front'), .7);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('panels side by side both fade as before', (tester) async {
    await _pump(
      tester,
      back: const Rect.fromLTWH(20, 20, 400, 300),
      front: const Rect.fromLTWH(600, 20, 400, 300),
    );
    expect(_opacity(tester, 'front'), .7);
    expect(_opacity(tester, 'back'), .7);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a faded panel turns opaque once it lies over another', (
    tester,
  ) async {
    Widget idle(bool covers) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: MenuPanelIdle(
          shown: true,
          coversPanel: covers,
          child: const SizedBox(
            width: 200,
            height: 200,
            child: Material(child: SizedBox.expand(key: ValueKey('content-x'))),
          ),
        ),
      ),
    );
    await tester.pumpWidget(idle(false));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_opacity(tester, 'x'), .7);
    await tester.pumpWidget(idle(true));
    await tester.pump();
    expect(_opacity(tester, 'x'), 1);
    await tester.pump(const Duration(seconds: 10));
    expect(_opacity(tester, 'x'), 1, reason: 'no fade while it covers one');
    await tester.pumpWidget(idle(false));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_opacity(tester, 'x'), .7, reason: 'moved apart, it fades again');
    await tester.pumpWidget(const SizedBox());
  });
}
