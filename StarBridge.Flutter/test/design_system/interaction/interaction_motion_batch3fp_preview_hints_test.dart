import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_editor_state.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_fixed_previews.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3s_test.dart' show Port;
import 'interaction_batch3do_test.dart' show loadFonts, scopedApp, size;

const _eventKey = Key('overlay-runtime-preview-event');

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Fixture {
  _Fixture(String mode) : selectionOnly = mode == 'selectionOnly' {
    editor.layoutLocked = mode == 'locked';
    editor.smartSnap = false;
    module = OverlayWorkspaceModule(port);
  }
  final Port port = Port();
  late final OverlayWorkspaceModule module;
  final editor = OverlayWorkspaceEditorState();
  final bool selectionOnly;
  final capture = GlobalKey();
  final before = FocusNode(debugLabel: 'before-preview');
  final after = FocusNode(debugLabel: 'after-preview');
  final placements = <(String, double)>[];
  int starts = 0, ends = 0, layoutChanges = 0, escapes = 0;
  Future<void> initialize() async {
    await module.refresh();
    module.updateSetting('showEventNotifications', true);
    module.updateSetting('showCrosshair', false);
    module.updateSetting('showChat', false);
    module.updateSetting('eventNotificationSide', 'Right');
    module.updateSetting('eventNotificationY', .34);
    // Setup edits save on their own; start each test from that saved state.
    await module.save();
    port.writes.clear();
  }

  Widget get preview => ValueListenableBuilder<OverlayWorkspaceProjection>(
    valueListenable: module.projection,
    builder: (context, projection, _) => OverlayWorkspaceLayoutWorkbench(
      controller: editor,
      layout: projection.layout,
      settings: projection.settings!,
      canvasOnly: true,
      fullScreen: true,
      selectionOnly: selectionOnly,
      showGrid: false,
      onChanged: (item, coalesce) {
        layoutChanges++;
        module.updateLayoutItem(item, coalesce: coalesce);
      },
      onEventNotificationPlacement: (side, y) {
        placements.add((side, y));
        module.updateEventNotificationPlacement(side, y);
      },
      onEventNotificationGestureStart: () {
        starts++;
        module.beginEventNotificationGesture();
      },
      onEventNotificationGestureEnd: () {
        ends++;
        module.endEventNotificationGesture();
      },
    ),
  );
  void resetObservations() {
    placements.clear();
    starts = 0;
    ends = 0;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    module.dispose();
    editor.dispose();
    before.dispose();
    after.dispose();
  }
}

Future<void> _mount(
  WidgetTester t,
  _Fixture f,
  InteractionSuite suite, {
  bool reduce = false,
}) async {
  await t.pumpWidget(
    RepaintBoundary(
      key: f.capture,
      child: scopedApp(
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () => f.escapes++,
          },
          child: Focus(
            autofocus: true,
            skipTraversal: true,
            child: SizedBox(
              width: 900,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    focusNode: f.before,
                    onPressed: () {},
                    child: const Text('Before preview'),
                  ),
                  f.preview,
                  TextButton(
                    focusNode: f.after,
                    onPressed: () {},
                    child: const Text('After preview'),
                  ),
                ],
              ),
            ),
          ),
        ),
        suite,
        reduce: reduce,
      ),
    ),
  );
  await _frames(t);
}

Finder get _hint => find.descendant(
  of: find.byType(OverlayWorkspaceFixedPreviews),
  matching: find.byType(StarBridgeTooltip),
);

SuiteTooltipState _hintState(WidgetTester t) => t.state<SuiteTooltipState>(
  find.descendant(of: _hint, matching: find.byType(SuiteTooltip)),
);

Future<void> _hover(WidgetTester t) async {
  final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(t.getCenter(find.byKey(_eventKey)));
  await _frames(t, 7);
}

Future<Uint8List> _pixels(WidgetTester t, _Fixture f) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(f.capture));
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final mode in ['draggable', 'locked', 'selectionOnly']) {
      testWidgets(
        '$suite $mode event hint preserves raw hover/longpress/drag contract',
        (t) async {
          size(t, const Size(1100, 850));
          final f = _Fixture(mode);
          await f.initialize();
          final saved = f.module.projection.value.snapshot;
          final originalSettings = f.module.projection.value.settings;
          final commands = f.port.runtimeCalls.length;
          final draggable = mode == 'draggable';
          try {
            await _mount(t, f, suite);
            expect(_hint, findsOneWidget);
            final hint = t.widget<StarBridgeTooltip>(_hint);
            final expected = draggable
                ? AppStrings.resolve(const Locale('zh', 'CN'))
                      .text('overlay.preview.eventDrag')
                : '';
            expect(hint.message, expected);
            expect(hint.consumeEscape, isFalse);
            final fixed = find.byType(OverlayWorkspaceFixedPreviews);
            expect(
              find.descendant(of: fixed, matching: find.byType(SuitePressable)),
              findsNothing,
            );
            expect(
              find.descendant(
                of: fixed,
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
              ),
              findsNothing,
            );
            await _hover(t);
            expect(_hintState(t).isShowing, draggable);
            expect(f.editor.selectedKey, isNull);
            expect(f.starts, 0);
            expect(f.ends, 0);
            expect(f.placements, isEmpty);
            expect(f.module.projection.value.settings, same(originalSettings));
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await _frames(t);
            expect(f.escapes, 1);
            expect(_hintState(t).isShowing, isFalse);
            await t.longPress(find.byKey(_eventKey));
            await _frames(t);
            expect(_hintState(t).isShowing, draggable);
            // Raw Listener intentionally selects at pointer-down, independently
            // of the long-press hint's gesture recognizer. This is not a save.
            expect(f.editor.selectedKey, 'Events');
            expect(f.starts, draggable ? 1 : 0);
            expect(f.ends, draggable ? 1 : 0);
            expect(f.placements, isEmpty);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await _frames(t);
            f.resetObservations();
            final beforeY =
                (f.module.projection.value.settings!['eventNotificationY']!
                        as num)
                    .toDouble();
            await t.drag(find.byKey(_eventKey), const Offset(-300, 60));
            await _frames(t);
            if (draggable) {
              expect(f.starts, 1);
              expect(f.ends, 1);
              expect(f.placements, isNotEmpty);
              expect(f.placements.last.$1, 'Left');
              expect(f.placements.last.$2, inInclusiveRange(0.0, 1.0));
              expect(f.placements.last.$2, isNot(beforeY));
              expect(
                f.module.projection.value.settings!['eventNotificationSide'],
                'Left',
              );
              expect(
                f.module.projection.value.settings!['eventNotificationY'],
                f.placements.last.$2,
              );
            } else {
              expect(f.starts, 0);
              expect(f.ends, 0);
              expect(f.placements, isEmpty);
              expect(
                f.module.projection.value.settings,
                same(originalSettings),
              );
            }
            if (draggable) {
              // The placement saved on its own.
              expect(
                f.port.writes.last.settings!['eventNotificationY'],
                f.placements.last.$2,
              );
            } else {
              expect(f.module.projection.value.snapshot, same(saved));
              expect(f.port.writes, isEmpty);
            }
            expect(f.port.runtimeCalls.length, commands);
            expect(f.layoutChanges, 0);
            expect(t.takeException(), isNull);
          } finally {
            await f.close(t);
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets(
      '$suite pointer cancel ends original placement gesture and keeps its placement',
      (t) async {
        size(t, const Size(1100, 850));
        final f = _Fixture('draggable');
        await f.initialize();
        try {
          await _mount(t, f, suite);
          final pointer = await t.startGesture(
            t.getCenter(find.byKey(_eventKey)),
          );
          await pointer.moveBy(const Offset(-300, 40));
          await _frames(t);
          expect(f.starts, 1);
          expect(f.placements, isNotEmpty);
          final latest = f.placements.last;
          await pointer.cancel();
          await _frames(t);
          expect(f.ends, 1);
          expect(
            f.module.projection.value.settings!['eventNotificationSide'],
            latest.$1,
          );
          expect(
            f.module.projection.value.settings!['eventNotificationY'],
            latest.$2,
          );
          expect(f.port.writes.last.settings!['eventNotificationY'], latest.$2);
          expect(t.takeException(), isNull);
        } finally {
          await f.close(t);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite preview hint adds no Tab stop between original controls',
      (t) async {
        size(t, const Size(1100, 850));
        final f = _Fixture('draggable');
        await f.initialize();
        try {
          await _mount(t, f, suite);
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pump();
          expect(FocusManager.instance.primaryFocus, same(f.before));
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pump();
          expect(FocusManager.instance.primaryFocus, same(f.after));
          expect(f.starts, 0);
          expect(f.placements, isEmpty);
          expect(f.port.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await f.close(t);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite live reduce and lock retire hint but keep same preview listener',
      (t) async {
        size(t, const Size(1100, 850));
        final f = _Fixture('draggable');
        await f.initialize();
        try {
          await _mount(t, f, suite);
          final listener = t.element(find.byKey(_eventKey));
          await _hover(t);
          expect(_hintState(t).isShowing, isTrue);
          await _mount(t, f, suite, reduce: true);
          expect(t.element(find.byKey(_eventKey)), same(listener));
          final before = await _pixels(t, f);
          await _frames(t, 3);
          expect(listEquals(before, await _pixels(t, f)), isTrue);
          f.editor.change(() => f.editor.layoutLocked = true);
          await _frames(t);
          expect(t.element(find.byKey(_eventKey)), same(listener));
          expect(t.widget<StarBridgeTooltip>(_hint).message, isEmpty);
          expect(_hintState(t).isShowing, isFalse);
          expect(f.starts, 0);
          expect(f.placements, isEmpty);
          expect(f.port.writes, isEmpty);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await _frames(t);
          expect(f.escapes, 1);
          expect(t.takeException(), isNull);
        } finally {
          await f.close(t);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
