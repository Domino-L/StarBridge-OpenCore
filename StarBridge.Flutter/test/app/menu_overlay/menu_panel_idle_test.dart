import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_panel_idle.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

void main() {
  double opacity(WidgetTester t) => t
      .widget<Opacity>(find.byKey(const ValueKey('menu-panel-idle-opacity')))
      .opacity;
  Widget app({bool shown = true, bool reducedMotion = true, Widget? child}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Align(
            alignment: Alignment.topLeft,
            child: MenuPanelIdle(
              shown: shown,
              child: SizedBox(
                width: 200,
                height: 200,
                child: Material(child: child ?? const Text('window')),
              ),
            ),
          ),
        ),
      );
  testWidgets(
    'five seconds idle starts a gradual fade; hover interrupts immediately',
    (t) async {
      await t.pumpWidget(app(reducedMotion: false));
      await t.pump(const Duration(milliseconds: 4999));
      expect(opacity(t), 1);
      await t.pump(const Duration(milliseconds: 1));
      expect(opacity(t), 1);
      await t.pump(const Duration(milliseconds: 110));
      expect(opacity(t), allOf(greaterThan(.7), lessThan(1)));
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(300, 300));
      await mouse.moveTo(const Offset(100, 100));
      await t.pump();
      expect(opacity(t), 1);
      await t.pump(const Duration(seconds: 8));
      expect(opacity(t), 1);
      await mouse.moveTo(const Offset(300, 300));
      await t.pump(const Duration(seconds: 5));
      expect(opacity(t), 1);
      await t.pump(const Duration(milliseconds: 110));
      expect(opacity(t), allOf(greaterThan(.7), lessThan(1)));
      await t.pump(const Duration(milliseconds: 110));
      expect(opacity(t), .7);
      await mouse.removePointer();
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('reduced motion applies the final opacity without a transition', (
    t,
  ) async {
    await t.pumpWidget(app());
    await t.pump(const Duration(seconds: 5));
    expect(opacity(t), .7);
    expect(t.hasRunningAnimations, isFalse);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'editing focus and native interaction protect but ordinary button focus does not',
    (t) async {
      final editing = FocusNode(), button = FocusNode();
      MenuPanelIdleScope? scope;
      await t.pumpWidget(
        app(
          child: Builder(
            builder: (context) {
              scope = MenuPanelIdleScope.of(context);
              return Column(
                children: [
                  TextField(focusNode: editing),
                  TextButton(
                    focusNode: button,
                    onPressed: () {},
                    child: const Text('button'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      editing.requestFocus();
      await t.pump();
      await t.pump(const Duration(seconds: 6));
      expect(opacity(t), 1);
      button.requestFocus();
      await t.pump();
      await t.pump(const Duration(seconds: 5));
      expect(opacity(t), .7);
      scope!.nativeInteraction(true);
      await t.pump();
      await t.pump(const Duration(seconds: 6));
      expect(opacity(t), 1);
      scope!.nativeInteraction(false);
      await t.pump(const Duration(seconds: 5));
      expect(opacity(t), .7);
      await t.pumpWidget(const SizedBox());
      editing.dispose();
      button.dispose();
    },
  );
  testWidgets(
    'popup and hidden state cancel timer while preserving content; disposal cancels timer',
    (t) async {
      const content = TextField(key: ValueKey('draft'));
      await t.pumpWidget(app(child: content));
      final state = t.state(find.byType(TextField));
      await t.pump(const Duration(seconds: 4));
      nativeViewportMenus.value++;
      await t.pump(const Duration(seconds: 10));
      expect(opacity(t), 1);
      nativeViewportMenus.value--;
      await t.pump(const Duration(seconds: 4));
      await t.pumpWidget(app(shown: false, child: content));
      await t.pump(const Duration(seconds: 10));
      expect(opacity(t), 1);
      expect(t.state(find.byType(TextField)), same(state));
      await t.pumpWidget(app(child: content));
      await t.pump(const Duration(seconds: 5));
      expect(opacity(t), .7);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('pressed drag stays opaque until release', (t) async {
    await t.pumpWidget(app());
    final drag = await t.startGesture(const Offset(80, 80));
    await drag.moveTo(const Offset(300, 300));
    await t.pump(const Duration(seconds: 8));
    expect(opacity(t), 1);
    await drag.up();
    await t.pump(const Duration(seconds: 5));
    expect(opacity(t), .7);
    await t.pumpWidget(const SizedBox());
  });
}
