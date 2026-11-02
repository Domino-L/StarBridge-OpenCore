import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3u_test.dart'
    show ColorHarness, ColorHarnessState, target;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

class EditorHarness extends StatefulWidget {
  const EditorHarness(this.initial, {super.key, this.frameKey});
  final InteractionSuite initial;
  final GlobalKey? frameKey;
  @override
  State<EditorHarness> createState() => EditorHarnessState();
}

class EditorHarnessState extends State<EditorHarness> {
  final controller = TextEditingController(text: '舰桥输入');
  final focus = FocusNode();
  late var suite = widget.initial;
  var reduce = false, light = false, invalid = false, enabled = true;
  var scale = 1.0;
  double slider = .4;
  int changes = 0, submitted = 0, sliding = 0;
  void change(VoidCallback action) => setState(action);
  Widget field({required bool framed}) {
    Widget native(FocusNode? node) => TextField(
      key: Key(framed ? 'framed' : 'native'),
      controller: framed ? controller : null,
      focusNode: node,
      enabled: enabled,
      showCursor: false,
      minLines: 2,
      maxLines: 3,
      maxLength: 24,
      decoration: InputDecoration(
        labelText: '预设名称',
        helperText: '保留输入与原有保存逻辑',
        errorText: invalid ? '名称不符合要求' : null,
      ),
      onChanged: framed ? (_) => changes++ : null,
      onSubmitted: framed ? (_) => submitted++ : null,
    );
    return framed
        ? StarBridgeFieldFrame(
            focusNode: focus,
            enabled: enabled,
            error: invalid,
            builder: (_, f) => native(f),
          )
        : native(null);
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => scopedApp(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(
        key: widget.frameKey,
        child: SizedBox(
          width: 420,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                field(framed: true),
                const SizedBox(height: 24),
                field(framed: false),
                StarBridgeFieldFrame(
                  cursor: SystemMouseCursors.click,
                  builder: (_, f) => Slider(
                    focusNode: f,
                    value: slider,
                    onChanged: (v) => setState(() {
                      slider = v;
                      sliding++;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite suite/theme/reduce preserve editor, selection and composing',
      (t) async {
        final key = GlobalKey<EditorHarnessState>();
        await t.pumpWidget(EditorHarness(suite, key: key));
        await t.pumpAndSettle();
        final state = key.currentState!;
        state.focus.requestFocus();
        await t.pump();
        final editor = find.descendant(
          of: find.byKey(const Key('framed')),
          matching: find.byType(EditableText),
        );
        final identity = t.state<EditableTextState>(editor);
        const value = TextEditingValue(
          text: '星海输入中',
          selection: TextSelection(baseOffset: 1, extentOffset: 4),
          composing: TextRange(start: 1, end: 4),
        );
        t.testTextInput.updateEditingValue(value);
        await t.pump();
        for (final next in InteractionSuite.values) {
          state.change(() {
            state.suite = next;
            state.reduce = !state.reduce;
            state.light = !state.light;
          });
          await t.pump();
          await t.pump();
          expect(t.state<EditableTextState>(editor), same(identity));
          expect(state.controller.value, value);
          expect(state.focus.hasFocus, isTrue);
        }
        expect(state.changes, 1);
        expect(state.submitted, 0);
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pump();
        expect(state.submitted, 1);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite intrinsic helper/error/counter height at 100 and 200 percent text',
      (t) async {
        size(t, const Size(700, 1100));
        final key = GlobalKey<EditorHarnessState>();
        await t.pumpWidget(EditorHarness(suite, key: key));
        for (final scale in [1.0, 2.0]) {
          for (final invalid in [false, true]) {
            key.currentState!.change(() {
              key.currentState!.scale = scale;
              key.currentState!.invalid = invalid;
            });
            await t.pumpAndSettle();
            expect(
              t.getSize(find.byKey(const Key('framed'))).height,
              t.getSize(find.byKey(const Key('native'))).height,
            );
            final frame = t.widget<SuiteFieldFrame>(
              find.byType(SuiteFieldFrame).first,
            );
            final total = t.getSize(find.byType(SuiteFieldFrame).first);
            final bounds = frame.boundsResolver!(total);
            expect(bounds.height, lessThan(total.height));
            expect(bounds.width, total.width);
            final label = frame.paintExclusionResolver!();
            expect(label, isNotNull);
            expect(label!.bottom, lessThanOrEqualTo(bounds.bottom));
            expect(label.left, greaterThanOrEqualTo(bounds.left));
            expect(t.takeException(), isNull);
          }
        }
      },
    );
    testWidgets(
      '$suite disabling uses original native field, external node not disposed',
      (t) async {
        final key = GlobalKey<EditorHarnessState>();
        await t.pumpWidget(EditorHarness(suite, key: key));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('framed')), '保留草稿');
        await t.pump();
        key.currentState!.change(() => key.currentState!.enabled = false);
        await t.pump();
        expect(key.currentState!.controller.text, '保留草稿');
        expect(
          t.widget<TextField>(find.byKey(const Key('framed'))).enabled,
          isFalse,
        );
        key.currentState!.change(() => key.currentState!.enabled = true);
        await t.pump();
        key.currentState!.focus.requestFocus();
        await t.pump();
        expect(key.currentState!.focus.hasFocus, isTrue);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('$suite native slider applies each active drag update', (
      t,
    ) async {
      final key = GlobalKey<EditorHarnessState>();
      await t.pumpWidget(EditorHarness(suite, key: key));
      await t.pumpAndSettle();
      final slider = find.byType(Slider);
      final gesture = await t.startGesture(t.getCenter(slider));
      for (var i = 1; i <= 5; i++) {
        await gesture.moveBy(const Offset(15, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await t.pump();
      expect(key.currentState!.sliding, greaterThanOrEqualTo(5));
      expect(key.currentState!.slider, greaterThan(.4));
      expect(t.takeException(), isNull);
    });
    testWidgets(
      '$suite real color draft validates and sliders keep original values',
      (t) async {
        size(t, const Size(900, 900));
        final key = GlobalKey<ColorHarnessState>();
        await t.pumpWidget(ColorHarness(suite, key: key));
        await t.pumpAndSettle();
        await target(t, const Key('overlay-color-open'), 'pointer');
        await t.pumpAndSettle();
        expect(find.byType(StarBridgeFieldFrame), findsNWidgets(4));
        await t.enterText(find.byKey(const Key('overlay-color-hex')), '#12');
        await t.pump();
        final frame = find.ancestor(
          of: find.byKey(const Key('overlay-color-hex')),
          matching: find.byType(StarBridgeFieldFrame),
        );
        expect(t.widget<StarBridgeFieldFrame>(frame).error, isTrue);
        expect(key.currentState!.changes, isEmpty);
        await t.enterText(
          find.byKey(const Key('overlay-color-hex')),
          '#123456',
        );
        await t.pump();
        expect(t.widget<StarBridgeFieldFrame>(frame).error, isFalse);
        final hue = t.widget<Slider>(
          find.byKey(const Key('overlay-color-hue')),
        );
        hue.onChanged!(.5);
        await t.pump();
        expect(key.currentState!.changes, isEmpty);
        await target(t, const Key('overlay-color-apply'), 'pointer');
        await t.pumpAndSettle();
        expect(key.currentState!.changes, hasLength(1));
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('$suite review focused input 200 percent text', (t) async {
      size(t, const Size(700, 1100));
      final key = GlobalKey<EditorHarnessState>(), frame = GlobalKey();
      await t.pumpWidget(EditorHarness(suite, key: key, frameKey: frame));
      key.currentState!.change(() {
        key.currentState!.scale = 2;
        key.currentState!.invalid = false;
      });
      key.currentState!.focus.requestFocus();
      await t.pump();
      await t.pump(const Duration(milliseconds: 900));
      final boundary =
          frame.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await t.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = (await img.toByteData(format: ImageByteFormat.png))!;
          final dir = Directory('build/reviews/interaction-batch3w')
            ..createSync(recursive: true);
          File('${dir.path}/${suite.name}-focused-200.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        } finally {
          img.dispose();
        }
      });
      expect(t.takeException(), isNull);
    });
  }
}
