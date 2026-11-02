import 'dart:ui' show SemanticsAction, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

Widget host(InteractionSuite suite, Widget child, {bool reduce = false}) =>
    InteractionScope(
      data: InteractionData(
        suite: suite,
        palette: palette,
        reduceMotion: reduce,
      ),
      child: MaterialApp(home: Scaffold(body: child)),
    );
void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite drag rendering clears immediately after release', (
      t,
    ) async {
      var value = .4;
      await t.pumpWidget(
        host(
          suite,
          StatefulBuilder(
            builder: (_, s) => SizedBox(
              width: 300,
              child: SuiteSlider(
                value: value,
                onChanged: (v) => s(() => value = v),
                onChangeEnd: (_) {},
              ),
            ),
          ),
        ),
      );
      final gesture = await t.startGesture(
        t.getCenter(find.byType(SuiteSlider)),
      );
      await gesture.moveBy(const Offset(40, 0));
      await t.pump();
      final painted = find.descendant(
        of: find.byType(SuiteSlider),
        matching: find.byType(CustomPaint),
      );
      expect(
        (t.widget<CustomPaint>(painted).painter as dynamic).dragging,
        true,
      );
      await gesture.up();
      await t.pump();
      expect(
        (t.widget<CustomPaint>(painted).painter as dynamic).dragging,
        false,
      );
      await t.pumpAndSettle();
    });
    testWidgets('$suite latest pointer input ends before paint', (t) async {
      var changed = .2;
      double? end;
      final origins = <InteractionSource>[];
      await t.pumpWidget(
        host(
          suite,
          SizedBox(
            width: 300,
            child: SuiteSlider(
              value: .2,
              onChanged: (v) => changed = v,
              onChangeEnd: (v) => end = v,
              onInputSource: origins.add,
            ),
          ),
        ),
      );
      final box = t.getRect(find.byType(SuiteSlider));
      final gesture = await t.startGesture(
        Offset(box.right - 20, box.center.dy),
      );
      await gesture.up();
      await t.pumpAndSettle();
      expect(end, changed);
      expect(end, greaterThan(.8));
      expect(origins.every((s) => s == InteractionSource.pointer), true);
    });
    testWidgets('$suite cancel never commits the pending pointer value', (
      t,
    ) async {
      var ended = 0, canceled = 0;
      await t.pumpWidget(
        host(
          suite,
          SizedBox(
            width: 300,
            child: SuiteSlider(
              value: .2,
              onChanged: (_) {},
              onChangeEnd: (_) => ended++,
              onChangeCancel: () => canceled++,
            ),
          ),
        ),
      );
      final box = t.getRect(find.byType(SuiteSlider));
      final gesture = await t.startGesture(box.center);
      await gesture.moveBy(const Offset(40, 0));
      await t.pump();
      await gesture.cancel();
      await t.pumpAndSettle();
      expect(ended, 0);
      expect(canceled, 1);
    });
    testWidgets('$suite reader interrupts hover decoration without value lag', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      var value = .4;
      InteractionSource? source;
      await t.pumpWidget(
        host(
          suite,
          StatefulBuilder(
            builder: (_, setState) => SizedBox(
              width: 300,
              child: SuiteSlider(
                value: value,
                divisions: 100,
                onInputSource: (s) => source = s,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );
      final hover = await t.createGesture(kind: PointerDeviceKind.mouse);
      await hover.addPointer(location: const Offset(700, 500));
      await hover.moveTo(t.getCenter(find.byType(SuiteSlider)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      final node = t.getSemantics(find.byType(SuiteSlider));
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.increase,
      );
      await t.pump();
      expect(value, closeTo(.41, .0001));
      expect(source, InteractionSource.keyboard);
      expect(t.binding.transientCallbackCount, 0);
      await hover.removePointer();
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    });
    testWidgets('$suite reduced busy text wraps inside narrow dialog width', (
      t,
    ) async {
      await t.pumpWidget(
        host(
          suite,
          const SizedBox(
            width: 110,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SuiteBusyLabel('Loading reminder settings…'),
            ),
          ),
          reduce: true,
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(SuiteBusyLabel)).width, 110);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }
}
