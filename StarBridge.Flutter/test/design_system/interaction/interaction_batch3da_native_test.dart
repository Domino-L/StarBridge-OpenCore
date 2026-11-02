import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_native_menu_item.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3cz_actions_test.dart' show exposed;
import 'interaction_batch3da_test.dart' show capture;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  for (final light in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      for (final enabled in [false, true]) {
        for (final selected in [false, true]) {
          for (final english in [false, true]) {
            testWidgets(
              'native geometry light=$light scale=$scale enabled=$enabled selected=$selected english=$english',
              (t) async {
                final focus = FocusNode();
                final native = GlobalKey(), adapter = GlobalKey();
                final semantics = t.ensureSemantics();
                final label = english ? 'Invisible mode' : '隐身状态';
                Widget body() => Row(
                  children: [
                    const Icon(Icons.circle, size: 8),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label)),
                    if (selected)
                      const Icon(Icons.check, size: 16)
                    else
                      const SizedBox(width: 16),
                  ],
                );
                try {
                  await t.pumpWidget(
                    scopedApp(
                      Builder(
                        builder: (context) => MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(textScaler: TextScaler.linear(scale)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RepaintBoundary(
                                key: native,
                                child: Material(
                                  child: SizedBox(
                                    width: 340,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) =>
                                          MenuItemButton(
                                            key: const Key('native-oracle'),
                                            closeOnActivate: false,
                                            onPressed: enabled ? () {} : null,
                                            child: SizedBox(
                                              width: constraints.maxWidth - 24,
                                              child: body(),
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              RepaintBoundary(
                                key: adapter,
                                child: Material(
                                  child: SizedBox(
                                    width: 340,
                                    child: StarBridgeNativeMenuItem(
                                      controlKey: const Key('native-adapter'),
                                      focusNode: focus,
                                      label: label,
                                      selected: selected,
                                      animated: true,
                                      onActivate: enabled ? (_) {} : null,
                                      child: body(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InteractionSuite.standard,
                      light: light,
                    ),
                  );
                  await t.pumpAndSettle();
                  (Size, Rect, double?, double?) sample(String id) {
                    final target = find.byKey(Key(id));
                    final rect = t.getRect(target);
                    final text = find.descendant(
                      of: target,
                      matching: find.byType(Text),
                    );
                    final style = DefaultTextStyle.of(t.element(text)).style;
                    return (
                      rect.size,
                      t.getRect(text).shift(-rect.topLeft),
                      style.fontSize,
                      style.letterSpacing,
                    );
                  }

                  expect(sample('native-adapter'), sample('native-oracle'));
                  expect(
                    await pixels(t, adapter),
                    orderedEquals(await pixels(t, native)),
                  );
                  final node = t.getSemantics(
                    find.byKey(const Key('native-adapter')),
                  );
                  var data = node.getSemanticsData();
                  if (node.isMergedIntoParent) {
                    data = node.parent!.getSemanticsData();
                  }
                  expect(data.label, label);
                  expect(data.hasAction(ui.SemanticsAction.tap), enabled);
                  expect(t.takeException(), isNull);
                } finally {
                  await t.pumpWidget(const SizedBox());
                  await t.pump();
                  semantics.dispose();
                  focus.dispose();
                }
              },
            );
          }
        }
      }
    }
    for (final interruption in ['reduce', 'keyboard', 'reader', 'cancel']) {
      testWidgets(
        'native press light=$light interruption=$interruption preserves feedback and intent',
        (t) async {
          final reduce = ValueNotifier(false);
          final focus = FocusNode();
          final boundary = GlobalKey();
          final calls = <InteractionSource>[];
          final semantics = t.ensureSemantics();
          try {
            await t.pumpWidget(
              ValueListenableBuilder<bool>(
                valueListenable: reduce,
                builder: (context, value, _) => scopedApp(
                  RepaintBoundary(
                    key: boundary,
                    child: Material(
                      child: SizedBox(
                        width: 340,
                        child: StarBridgeNativeMenuItem(
                          controlKey: const Key('native-adapter'),
                          focusNode: focus,
                          label: '隐身状态',
                          animated: !value,
                          onActivate: calls.add,
                          child: const Text('隐身状态'),
                        ),
                      ),
                    ),
                  ),
                  InteractionSuite.standard,
                  light: light,
                  reduce: value,
                ),
              ),
            );
            await t.pumpAndSettle();
            final idle = await pixels(t, boundary);
            final press = await t.startGesture(
              t.getCenter(find.byKey(const Key('native-adapter'))),
            );
            await t.pump();
            await t.pump(const Duration(milliseconds: 30));
            final pressed = await pixels(t, boundary);
            expect(pressed, isNot(orderedEquals(idle)));
            await capture(t, boundary, 'native-pressed-$light-$interruption');
            expect(calls, isEmpty);
            if (interruption == 'reduce') {
              reduce.value = true;
            } else if (interruption == 'keyboard') {
              focus.requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
              expect(calls, [InteractionSource.keyboard]);
            } else if (interruption == 'reader') {
              final node = exposed(t, 'native-adapter');
              t.binding.performSemanticsAction(
                ui.SemanticsActionEvent(
                  type: ui.SemanticsAction.tap,
                  viewId: t.view.viewId,
                  nodeId: node.id,
                ),
              );
              expect(calls, [InteractionSource.keyboard]);
            } else {
              await press.cancel();
              await t.pumpAndSettle();
              expect(calls, isEmpty);
            }
            if (interruption != 'cancel') {
              await t.pump();
              await t.pump();
              final still = await pixels(t, boundary);
              await t.pump(const Duration(milliseconds: 80));
              expect(await pixels(t, boundary), orderedEquals(still));
              await press.up();
              // MenuItemButton deliberately dispatches onPressed post-frame.
              await t.pump();
              expect(calls.last, InteractionSource.pointer);
              expect(calls.length, interruption == 'reduce' ? 1 : 2);
            }
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pump();
            semantics.dispose();
            focus.dispose();
            reduce.dispose();
          }
        },
      );
    }
  }
}
