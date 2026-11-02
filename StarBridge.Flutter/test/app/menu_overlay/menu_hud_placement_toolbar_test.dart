import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_hud_placement_bars.dart';

void main() {
  testWidgets('the toolbar grip is a labelled 32 px target that drags', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var drags = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MenuHudPlacementToolbar(
            text: (key, [args = const {}]) => key.split('.').last,
            presetName: 'P',
            changed: false,
            grid: true,
            align: false,
            canUndo: false,
            canRedo: false,
            hidden: const {},
            hiddenOpen: false,
            busy: false,
            onDrag: (_) => drags++,
            onGrid: () {},
            onAlign: () {},
            onUndo: () {},
            onRedo: () {},
            onHiddenOpen: () {},
            onShow: (_) {},
            onCancel: () {},
            onDone: () {},
          ),
        ),
      ),
    );
    final grip = find.byKey(const ValueKey('menu-hud-place-toolbar-grip'));
    final size = tester.getSize(grip);
    expect(size.width, greaterThanOrEqualTo(32));
    expect(size.height, greaterThanOrEqualTo(32));
    expect(find.bySemanticsLabel('moveToolbar'), findsOneWidget);
    // Away from the icon, near the grip's edge, still grabs.
    final edge = tester.getTopLeft(grip) + const Offset(3, 3);
    await tester.dragFrom(edge, const Offset(30, 0));
    expect(drags, greaterThan(0));
    expect(find.text('✓ grid'), findsOneWidget);
    expect(find.text('align'), findsOneWidget);
  });
}
