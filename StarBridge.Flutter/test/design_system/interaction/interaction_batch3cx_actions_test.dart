import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_dock.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_controls.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3cx_test.dart' show fixture, target;

FocusNode bridgeFocus(WidgetTester t, Finder target) {
  final actual = find
      .descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (w) => w is FocusableActionDetector || w is SuitePressable,
        ),
      )
      .first;
  return switch (t.widget(actual)) {
    FocusableActionDetector(:final focusNode) => focusNode!,
    SuitePressable(:final focusNode) => focusNode!,
    _ => throw StateError('No focus target'),
  };
}

Future<void> fire(WidgetTester t, String source, Finder target) async {
  expect(target, findsOneWidget);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    bridgeFocus(t, target).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        viewId: t.view.viewId,
        nodeId: node.id,
      ),
    );
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final id in ['dock', 'friends', 'refresh', 'hangar']) {
        testWidgets('$suite $source $id keeps original immediate intent', (
          t,
        ) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = const Size(1200, 900);
          final semantics = t.ensureSemantics();
          final calls = <(String, InteractionSource)>[];
          try {
            await t.pumpWidget(
              host(
                fixture(
                  id == 'refresh' ? 'friends' : id,
                  record: (v) =>
                      calls.add((v, captureStarBridgeActivationSource()())),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            if (id == 'friends' || id == 'refresh') {
              await t.enterText(
                find.byKey(const ValueKey('friends-account-search')),
                '保留查询',
              );
            }
            final actual = id == 'refresh'
                ? find.byKey(const ValueKey('friends-refresh-'))
                : target(id);
            await fire(t, source, actual);
            expect(calls, [
              (
                switch (id) {
                  'dock' => 'friends',
                  'friends' => 'search||保留查询',
                  'refresh' => 'refresh||',
                  _ => 'open',
                },
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            ]);
            expect(
              captureStarBridgeActivationSource()(),
              InteractionSource.programmatic,
            );
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await detach(t);
            t.view.reset();
          }
        });
      }
    }
    testWidgets(
      '$suite live style preserves full search editing value and busy gating',
      (t) async {
        var style = suite, busy = false;
        var reduced = false;
        late StateSetter update;
        final calls = <String>[];
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  SizedBox(
                    width: 600,
                    child: MenuFriendsControls(
                      view: MenuFriendsView(
                        'ready',
                        interactive: true,
                        busy: busy,
                      ),
                      onAction: (a, k, v) => calls.add('$a|$k|$v'),
                    ),
                  ),
                  style,
                  reduce: reduced,
                );
              },
            ),
          );
          await t.pumpAndSettle();
          final field = find.byKey(const ValueKey('friends-account-search'));
          final editor = t.widget<TextField>(field).controller!;
          const draft = TextEditingValue(
            text: '舰桥查询',
            selection: TextSelection(baseOffset: 1, extentOffset: 3),
            composing: TextRange(start: 1, end: 3),
          );
          editor.value = draft;
          update(() {
            style = InteractionSuite.values[(suite.index + 1) % 4];
            reduced = true;
            busy = true;
          });
          await t.pump();
          await t.pump();
          expect(t.widget<TextField>(field).controller, same(editor));
          expect(editor.value, draft);
          await t.tapAt(t.getCenter(target('friends')));
          await t.pump();
          expect(calls, isEmpty);
          expect(t.widget<TextField>(field).readOnly, isTrue);
          update(() => busy = false);
          await t.pump();
          await t.showKeyboard(field);
          await t.testTextInput.receiveAction(TextInputAction.search);
          await t.pump();
          expect(calls, ['search||舰桥查询']);
          expect(editor.text, draft.text);
          expect(editor.selection, draft.selection);
          expect(editor.value.composing, TextRange.empty);
        } finally {
          await detach(t);
        }
      },
    );
    for (final select in [false, true]) {
      testWidgets(
        '$suite existing right-click recover remains explicit select=$select',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = const Size(1200, 900);
          final recovered = <BridgePreviewPanel>[];
          final toggled = <BridgePreviewPanel>[];
          try {
            await t.pumpWidget(
              host(
                BridgePreviewDock(
                  selected: BridgePreviewPanel.friends,
                  openPanels: const {BridgePreviewPanel.friends},
                  onToggle: toggled.add,
                  onRecover: recovered.add,
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await t.tap(target('dock'), buttons: kSecondaryMouseButton);
            await t.pumpAndSettle();
            expect(find.text('移回当前屏幕'), findsOneWidget);
            expect(recovered, isEmpty);
            expect(toggled, isEmpty);
            if (select) {
              await t.tap(find.text('移回当前屏幕'));
            } else {
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
            }
            await t.pumpAndSettle();
            expect(recovered, select ? [BridgePreviewPanel.friends] : isEmpty);
            expect(toggled, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await detach(t);
            t.view.reset();
          }
        },
      );
    }
  }
}
