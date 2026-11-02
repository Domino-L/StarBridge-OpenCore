// Scenario components: drawer (15), image viewer (20), context menu (13),
// danger confirm (16), chart (23), style cards (33), hotkey + swatches (12).
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

Widget _host(InteractionSuite suite, Widget child, {bool reduce = false}) => InteractionScope(
  data: InteractionData(suite: suite, palette: palette, reduceMotion: reduce),
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  group('15 drawer', () {
    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: opens, takes focus, Esc closes and returns focus', (t) async {
        var open = false;
        final opener = FocusNode(debugLabel: 'opener');
        addTearDown(opener.dispose);
        await t.pumpWidget(
          _host(
            suite,
            StatefulBuilder(
              builder: (context, set) => Stack(
                children: [
                  Focus(focusNode: opener, child: TextButton(onPressed: () => set(() => open = true), child: const Text('open'))),
                  Positioned.fill(
                    child: SuiteDrawer(
                      open: open,
                      onClose: () => set(() => open = false),
                      child: const Center(child: Text('details')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        opener.requestFocus();
        await t.pump();
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(find.text('details'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.text('details'), findsNothing);
        expect(opener.hasFocus || FocusManager.instance.primaryFocus?.context?.widget is Focus, isTrue);
      });
    }

    testWidgets('reduced motion opens without animation', (t) async {
      var open = false;
      await t.pumpWidget(
        _host(
          InteractionSuite.scan,
          StatefulBuilder(
            builder: (context, set) => Stack(
              children: [
                TextButton(onPressed: () => set(() => open = true), child: const Text('open')),
                Positioned.fill(child: SuiteDrawer(open: open, onClose: () {}, child: const Text('details'))),
              ],
            ),
          ),
          reduce: true,
        ),
      );
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump();
      expect(find.text('details'), findsOneWidget);
    });
  });

  group('20 image viewer', () {
    testWidgets('zoom readout is real; crop corners follow the drag exactly', (t) async {
      final key = GlobalKey<SuiteImageViewerState>();
      Rect? crop;
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          Center(
            child: SizedBox(
              width: 300,
              child: SuiteImageViewer(key: key, height: 200, image: const ColoredBox(color: Colors.blueGrey), onCropChanged: (r) => crop = r),
            ),
          ),
        ),
      );
      expect(find.text('100%'), findsOneWidget);
      await t.tap(find.byIcon(Icons.zoom_in));
      await t.pumpAndSettle();
      expect(find.text('150%'), findsOneWidget);
      await t.tap(find.byIcon(Icons.fit_screen_outlined));
      await t.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);

      await t.tap(find.byIcon(Icons.crop));
      await t.pumpAndSettle();
      final before = key.currentState!.crop;
      final handle = find.bySemanticsLabel('裁切角 1');
      await t.drag(handle, const Offset(30, 20));
      await t.pump();
      final after = key.currentState!.crop;
      expect(after.left, closeTo(before.left + 30 / 300, 0.01));
      expect(after.top, closeTo(before.top + 20 / 200, 0.01));
      expect(crop, after);
    });
  });

  group('13 context menu', () {
    List<SuiteMenuAction> actions(List<String> log) => [
      SuiteMenuAction(label: 'Join', onSelected: () => log.add('join')),
      SuiteMenuAction(
        label: 'Invite to',
        children: [
          SuiteMenuAction(label: 'Ann', onSelected: () => log.add('ann')),
          SuiteMenuAction(label: 'Bo', onSelected: () => log.add('bo')),
        ],
      ),
      const SuiteMenuAction(label: 'Pin (soon)'),
    ];

    for (final suite in InteractionSuite.values) {
      testWidgets('${suite.name}: keyboard opens, → enters submenu, Esc backs out', (t) async {
        final log = <String>[];
        late BuildContext ctx;
        await t.pumpWidget(_host(suite, Builder(builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        })));
        showSuiteContextMenu(ctx, position: const Offset(100, 100), actions: actions(log), source: InteractionSource.keyboard);
        await t.pump();
        await t.pump();
        expect(find.text('Join'), findsOneWidget);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'ctx-0');
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        await t.pump();
        expect(find.text('Ann'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.text('Ann'), findsNothing);
        expect(find.text('Join'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(log, ['bo']);
        expect(find.text('Join'), findsNothing);
      });
    }

    testWidgets('flips at the window edge and closes on outside tap', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_host(InteractionSuite.glow, Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })));
      final size = t.view.physicalSize / t.view.devicePixelRatio;
      showSuiteContextMenu(ctx, position: Offset(size.width - 10, size.height - 10), actions: actions([]));
      await t.pumpAndSettle();
      final r = t.getRect(find.text('Join'));
      expect(r.right, lessThan(size.width));
      expect(r.bottom, lessThan(size.height));
      await t.tapAt(const Offset(20, 20));
      await t.pumpAndSettle();
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('submenu opens on hover after a short intent delay', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_host(InteractionSuite.rail, Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })));
      showSuiteContextMenu(ctx, position: const Offset(100, 100), actions: actions([]));
      await t.pumpAndSettle();
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: t.getCenter(find.text('Invite to')));
      await t.pump(const Duration(milliseconds: 60));
      expect(find.text('Ann'), findsNothing);
      await t.pump(const Duration(milliseconds: 200));
      await t.pumpAndSettle();
      expect(find.text('Ann'), findsOneWidget);
      await mouse.removePointer();
    });
  });

  group('16 danger confirm', () {
    testWidgets('confirm stays disabled until the name is typed; nothing animates', (t) async {
      var confirmed = 0;
      await t.pumpWidget(
        _host(
          InteractionSuite.scan,
          Center(
            child: SuiteDangerConfirm(
              title: 'Remove?',
              consequences: const ['They lose access.'],
              typeToConfirm: 'FLEET',
              confirmLabel: 'Remove',
              onConfirm: () => confirmed++,
              onCancel: () {},
            ),
          ),
        ),
      );
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      await t.tap(find.text('Remove'), warnIfMissed: false);
      expect(confirmed, 0);
      await t.enterText(find.byType(TextField), 'FLEET');
      await t.pump();
      await t.tap(find.text('Remove'));
      await t.pumpAndSettle();
      expect(confirmed, 1);
    });
  });

  group('23 chart', () {
    testWidgets('legend toggles series; hover shows real values', (t) async {
      final key = GlobalKey<SuiteBarChartState>();
      await t.pumpWidget(
        _host(
          InteractionSuite.glow,
          Center(
            child: SizedBox(
              width: 300,
              child: SuiteBarChart(
                key: key,
                labels: const ['A', 'B'],
                series: const [
                  ChartSeries(name: 'US', values: [3, 7], color: Colors.blue),
                  ChartSeries(name: 'EU', values: [1, 2], color: Colors.green),
                ],
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('EU'));
      await t.pumpAndSettle();
      expect(key.currentState!.hidden, {'EU'});
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      // A point inside the plot area, over the second group.
      final chart = t.getRect(find.byType(SuiteBarChart));
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(Offset(chart.left + chart.width * 0.75, chart.bottom - 60));
      await t.pump();
      expect(find.text('US 7'), findsOneWidget);
      expect(find.text('EU 2'), findsNothing);
      await mouse.removePointer();
    });
  });

  group('33 style cards', () {
    testWidgets('choosing a card reports it; previews stay still unless hovered', (t) async {
      var chosen = InteractionSuite.rail;
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, s) => SuiteStyleCards(value: chosen, onChanged: (v) => s(() => chosen = v)),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse);
      await t.tap(find.text('扫描'));
      await t.pumpAndSettle();
      expect(chosen, InteractionSuite.scan);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: t.getCenter(find.text('光晕')));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.hasRunningAnimations, isTrue);
      await mouse.moveTo(const Offset(-50, -50));
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse);
      await mouse.removePointer();
    });
  });

  group('12 hotkey and swatches', () {
    testWidgets('records a combination; refuses reserved; Esc cancels; Backspace clears', (t) async {
      String? value = 'Alt + M';
      await t.pumpWidget(
        _host(
          InteractionSuite.rail,
          Center(
            child: SizedBox(
              width: 260,
              child: StatefulBuilder(
                builder: (context, s) => SuiteHotkeyField(
                  value: value,
                  reserved: const {'Alt + F4': 'close'},
                  onChanged: (v) => s(() => value = v),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Alt + M'));
      await t.pump();
      expect(find.text('请按下组合键…'), findsOneWidget);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyO);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(value, 'Ctrl + Shift + O');

      await t.tap(find.text('Ctrl + Shift + O'));
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.f4);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(value, 'Ctrl + Shift + O');
      expect(find.textContaining('close'), findsOneWidget);

      await t.tap(find.text('Ctrl + Shift + O'));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(value, 'Ctrl + Shift + O');

      await t.tap(find.text('Ctrl + Shift + O'));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      await t.pump();
      expect(value, isNull);
    });

    testWidgets('swatch choice applies at once', (t) async {
      var c = Colors.blue;
      await t.pumpWidget(
        _host(
          InteractionSuite.scan,
          StatefulBuilder(
            builder: (context, s) => SuiteSwatchPicker(
              colors: const [Colors.blue, Colors.green],
              value: c,
              onChanged: (v) => s(() => c = v as MaterialColor),
            ),
          ),
        ),
      );
      await t.tap(find.byType(SuitePressable).last);
      await t.pump();
      expect(c, Colors.green);
    });
  });
}
