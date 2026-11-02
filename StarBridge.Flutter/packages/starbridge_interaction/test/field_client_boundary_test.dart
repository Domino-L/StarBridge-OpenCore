import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

AnimationController frameAnimation(WidgetTester t) {
  final paints = t.widgetList<CustomPaint>(
    find.descendant(
      of: find.byType(SuiteFieldFrame),
      matching: find.byType(CustomPaint),
    ),
  );
  final painter = paints
      .expand((p) => [p.painter, p.foregroundPainter])
      .firstWhere((p) => p.runtimeType.toString() == '_FieldPainter');
  return (painter as dynamic).focus as AnimationController;
}

class Harness extends StatefulWidget {
  const Harness(this.initial, {super.key});
  final InteractionSuite initial;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  final first = FocusNode(), second = FocusNode();
  late var suite = widget.initial;
  var enabled = true, reduce = false, swapped = false;
  FocusNode get focus => swapped ? second : first;
  void change(VoidCallback action) => setState(action);
  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: InteractionScope(
        data: InteractionData(
          suite: suite,
          palette: palette,
          reduceMotion: reduce,
        ),
        child: Column(
          children: [
            SizedBox(
              width: 280,
              child: SuiteFieldFrame(
                focusNode: focus,
                height: null,
                foregroundOnly: true,
                enabled: enabled,
                child: TextField(
                  focusNode: focus,
                  enabled: enabled,
                  showCursor: false,
                  onTapOutside: (_) => focus.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Input',
                    helperText: 'Help',
                  ),
                ),
              ),
            ),
            const SizedBox(
              height: 100,
              width: 280,
              child: Focus(child: Text('outside')),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite pointer retains feedback, programmatic refocus is immediate',
      (t) async {
        final key = GlobalKey<HarnessState>();
        await t.pumpWidget(Harness(suite, key: key));
        await t.tap(find.byType(TextField));
        await t.pump();
        expect(key.currentState!.focus.hasFocus, isTrue);
        expect(
          frameAnimation(t).isAnimating,
          suite != InteractionSuite.standard,
        );
        key.currentState!.focus.unfocus();
        await t.pump();
        key.currentState!.focus.requestFocus();
        await t.pump();
        expect(frameAnimation(t).value, 1);
        expect(frameAnimation(t).isAnimating, isFalse);
      },
    );
    testWidgets('$suite typing clears intro, Tab blur is immediate', (t) async {
      await t.pumpWidget(Harness(suite));
      await t.tap(find.byType(TextField));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.keyA);
      await t.pump();
      expect(frameAnimation(t).value, 1);
      expect(frameAnimation(t).isAnimating, isFalse);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(frameAnimation(t).value, 0);
      expect(frameAnimation(t).isAnimating, isFalse);
    });
    testWidgets('$suite pointer outside retains exit feedback', (t) async {
      await t.pumpWidget(Harness(suite));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      await t.tap(find.text('outside'));
      await t.pump();
      expect(frameAnimation(t).isAnimating, suite != InteractionSuite.standard);
      await t.pumpAndSettle();
      expect(frameAnimation(t).value, 0);
    });
    testWidgets(
      '$suite reduced motion settles and disabled focus does not decorate',
      (t) async {
        final key = GlobalKey<HarnessState>();
        await t.pumpWidget(Harness(suite, key: key));
        await t.tap(find.byType(TextField));
        await t.pump();
        key.currentState!.change(() => key.currentState!.reduce = true);
        await t.pump();
        expect(frameAnimation(t).isAnimating, isFalse);
        expect(frameAnimation(t).value, 1);
        key.currentState!.change(() => key.currentState!.enabled = false);
        await t.pump();
        expect(frameAnimation(t).value, 0);
        await t.pumpWidget(const SizedBox());
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite replacement focus node settles without retaining old listener',
      (t) async {
        final key = GlobalKey<HarnessState>();
        await t.pumpWidget(Harness(suite, key: key));
        await t.tap(find.byType(TextField));
        await t.pump();
        key.currentState!.change(() => key.currentState!.swapped = true);
        await t.pump();
        expect(frameAnimation(t).value, 0);
        key.currentState!.second.requestFocus();
        await t.pump();
        expect(frameAnimation(t).value, 1);
        expect(frameAnimation(t).isAnimating, isFalse);
        key.currentState!.first.requestFocus();
        await t.pump();
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('$suite switching suite preserves focused final cue', (
      t,
    ) async {
      final key = GlobalKey<HarnessState>();
      await t.pumpWidget(Harness(suite, key: key));
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      key.currentState!.change(
        () => key.currentState!.suite = InteractionSuite.rail,
      );
      await t.pump();
      expect(frameAnimation(t).value, 1);
      expect(frameAnimation(t).isAnimating, isFalse);
    });
  }
}
