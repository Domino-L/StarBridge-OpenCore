import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_controls.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';

import 'interaction_batch3i_test.dart' show scopedApp;

Finder action(String title) =>
    find.byWidgetPredicate((w) => w is MenuImageAction && w.title == title);

class ImageHarness extends StatefulWidget {
  const ImageHarness(
    this.tools,
    this.suite, {
    this.capture = false,
    this.workspace,
    this.imageKey,
    super.key,
  });
  final MenuLocalToolsController tools;
  final InteractionSuite suite;
  final bool capture;
  final MenuWorkspaceController? workspace;
  final GlobalKey? imageKey;
  @override
  State<ImageHarness> createState() => ImageHarnessState();
}

class ImageHarnessState extends State<ImageHarness> {
  late MenuLocalToolsController tools = widget.tools;
  late InteractionSuite suite = widget.suite;
  bool reduce = false, light = false, shown = true;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    shown
        ? MenuImageTool(
            key: widget.imageKey,
            tools: tools,
            capture: widget.capture,
            workspace: widget.workspace,
          )
        : const SizedBox(),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<void> frames(WidgetTester t, [int count = 3]) async {
  for (var i = 0; i < count; i++) {
    await t.pump();
  }
}

Future<void> painted(WidgetTester t, {bool Function()? until}) async {
  for (var attempt = 0; attempt < (until == null ? 1 : 100); attempt++) {
    await frames(t);
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await frames(t);
    if (until == null || until()) return;
  }
  expect(
    until!(),
    isTrue,
    reason: 'Native image capture did not reach its held command.',
  );
}

Future<void> fire(WidgetTester t, String label, String source) async {
  final target = action(label);
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'reader') {
    final text = find.descendant(of: target, matching: find.text(label));
    final semantics = find
        .ancestor(
          of: text,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.onTap != null,
          ),
        )
        .first;
    final node = t.getSemantics(semantics);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    final material = find.descendant(
      of: target,
      matching: find.byType(OutlinedButton),
    );
    final focus = material.evaluate().isNotEmpty
        ? t.widget<OutlinedButton>(material).focusNode!
        : t
              .widget<SuitePressable>(
                find.descendant(
                  of: target,
                  matching: find.byType(SuitePressable),
                ),
              )
              .focusNode!;
    focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(
      source == 'space'
          ? LogicalKeyboardKey.space
          : source == 'numpad'
          ? LogicalKeyboardKey.numpadEnter
          : LogicalKeyboardKey.enter,
    );
  }
  await frames(t);
}

Future<void> cache(WidgetTester t, Uint8List bytes) async {
  await frames(t);
  await t.runAsync(
    () => precacheImage(
      MemoryImage(bytes),
      t.element(find.byType(MenuImageTool)),
    ),
  );
  await frames(t);
}

MenuLocalToolsController owner(
  Uint8List png,
  Future<Object?> Function(String, Map<String, Object?>) call, {
  bool capture = false,
}) {
  final tools = MenuLocalToolsController(call)..referenceAutoPinOnClose = false;
  if (capture) {
    tools.screenshot = tools.screenshotPreview = png;
  } else {
    tools.reference = png;
  }
  return tools;
}
