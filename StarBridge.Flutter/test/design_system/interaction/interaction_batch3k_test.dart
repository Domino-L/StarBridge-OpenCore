import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog_surface.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp, keyPress, dialogAction;

Finder get surface => find.descendant(
  of: find.byType(StarBridgeDialogSurface),
  matching: find.byType(SuiteSurfaceTransition),
);
Finder get panel => find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;

void checkBounds(WidgetTester t) {
  final transition = t.widget<SuiteSurfaceTransition>(surface);
  final nativeRect = t.getRect(panel);
  final canvas = t.getRect(surface);
  expect(transition.surfaceBounds, nativeRect.shift(-canvas.topLeft));
  expect(transition.surfaceBounds!.width, lessThan(canvas.width));
  expect(transition.surfaceBounds!.height, lessThan(canvas.height));
}

Future<Uint8List> pixels(WidgetTester t, GlobalKey key, String name) async {
  return (await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final raw = await image.toByteData(format: ImageByteFormat.rawRgba);
      if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3K'] == '1') {
        final png = await image.toByteData(format: ImageByteFormat.png);
        final dir = Directory('build/reviews/interaction-batch3k');
        await dir.create(recursive: true);
        await File('${dir.path}/$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
      }
      return raw!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite alert artwork follows native Material rather than viewport',
      (t) async {
        size(t, const Size(1000, 800));
        final frame = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: scopedApp(
              Builder(
                builder: (context) => Center(
                  child: StarBridgeActionButton(
                    onActivate: (source) => showStarBridgeDialog<void>(
                      context,
                      source: source,
                      builder: (context) => AlertDialog(
                        title: const Text('弹窗表面检查'),
                        content: const SizedBox(
                          width: 300,
                          height: 130,
                          child: Text('边缘装饰应贴合这个弹窗。'),
                        ),
                        actions: [
                          StarBridgeActionButton(
                            kind: StarBridgeActionKind.quiet,
                            onActivate: (source) => dismissStarBridgeDialog(
                              context,
                              source: source,
                            ),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('打开'),
                  ),
                ),
              ),
              suite,
            ),
          ),
        );
        await t.pumpAndSettle();
        await keyPress(t, find.widgetWithText(StarBridgeActionButton, '打开'));
        checkBounds(t);
        final data = await pixels(t, frame, '${suite.name}-alert-settled');
        // The rail previously painted along the screen's first row. Compare
        // the same x outside the dialog and its shadow, not a whole-screen hash.
        final top = (500 * 4), below = (10 * 1000 + 500) * 4;
        expect(data.sublist(top, top + 4), data.sublist(below, below + 4));
        await keyPress(t, dialogAction('关闭'));
        expect(find.byType(Dialog), findsNothing);
        // Pointer entry still uses the approved motion; its drawing bounds
        // remain the untransformed panel rather than the viewport.
        await t.tap(find.widgetWithText(StarBridgeActionButton, '打开'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        final moving = t.widget<SuiteSurfaceTransition>(surface);
        expect(moving.animation.value, greaterThan(0));
        expect(moving.animation.value, lessThan(1));
        expect(moving.surfaceBounds!.width, lessThan(500));
        expect(moving.surfaceBounds!.height, lessThan(500));
        await pixels(t, frame, '${suite.name}-alert-entering');
        await t.pumpAndSettle();
        checkBounds(t);
        await t.tap(dialogAction('关闭'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(find.byType(Dialog), findsOneWidget);
        await t.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(t.binding.hasScheduledFrame, false);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite custom aligned dialog remeasures resize without remounting draft',
      (t) async {
        size(t, const Size(1000, 800));
        var width = 280.0, height = 160.0;
        var alignment = Alignment.topRight;
        late StateSetter changeContent;
        final controller = TextEditingController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) => Center(
                child: StarBridgeActionButton(
                  onActivate: (source) => showStarBridgeDialog<void>(
                    context,
                    source: source,
                    builder: (context) => StatefulBuilder(
                      builder: (context, setState) {
                        changeContent = setState;
                        return Dialog(
                          alignment: alignment,
                          insetPadding: const EdgeInsets.all(60),
                          child: SizedBox(
                            width: width,
                            height: height,
                            child: Column(
                              children: [
                                TextField(
                                  controller: controller,
                                  focusNode: focus,
                                ),
                                StarBridgeActionButton(
                                  onActivate: (source) =>
                                      dismissStarBridgeDialog(
                                        context,
                                        source: source,
                                      ),
                                  child: const Text('关闭'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await keyPress(t, find.widgetWithText(StarBridgeActionButton, '打开'));
        checkBounds(t);
        expect(t.getRect(panel).right, 940);
        expect(t.getRect(panel).top, 60);
        await t.enterText(find.byType(TextField), '保留草稿');
        final editor = t.state<EditableTextState>(find.byType(EditableText));
        changeContent(() {
          width = 360;
          height = 220;
          alignment = Alignment.bottomLeft;
        });
        await t.pump();
        await t.pump();
        checkBounds(t);
        expect(t.getRect(panel).left, 60);
        expect(t.getRect(panel).bottom, 740);
        expect(
          t.state<EditableTextState>(find.byType(EditableText)),
          same(editor),
        );
        expect(controller.text, '保留草稿');
        expect(focus.hasFocus, true);
        await keyPress(t, find.widgetWithText(StarBridgeActionButton, '关闭'));
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(t.binding.hasScheduledFrame, false);
        expect(t.takeException(), isNull);
      },
    );
  }
}
