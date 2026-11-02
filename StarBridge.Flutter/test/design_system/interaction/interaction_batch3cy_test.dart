import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_dock.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3cx_actions_test.dart' show bridgeFocus;

Widget dock({
  required ValueChanged<BridgePreviewPanel> toggle,
  required ValueChanged<BridgePreviewPanel> recover,
}) => BridgePreviewDock(
  selected: BridgePreviewPanel.friends,
  openPanels: const {BridgePreviewPanel.friends},
  onToggle: toggle,
  onRecover: recover,
);
final friend = find.byKey(const ValueKey('menu-tool-friends'));
SemanticsNode exposedFriend(
  WidgetTester t, {
  String label = '好友',
  Finder? target,
}) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode n) {
    if (n.isMergedIntoParent) return;
    final data = n.getSemanticsData();
    if (data.label == label && data.flagsCollection.isButton) nodes.add(n);
    n.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  var root = t.getSemantics(target ?? friend);
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  expect(nodes, hasLength(1));
  return nodes.single;
}

Future<void> openContext(WidgetTester t, String source) async {
  if (source == 'pointer') {
    await t.tap(friend, buttons: kSecondaryMouseButton);
  } else if (source == 'reader') {
    final node = exposedFriend(t);
    final ids = node.getSemanticsData().customSemanticsActionIds!;
    final id = ids.singleWhere(
      (id) => CustomSemanticsAction.getAction(id)!.label == '移回当前屏幕',
    );
    t.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.customAction,
        viewId: t.view.viewId,
        nodeId: node.id,
        arguments: id,
      ),
    );
  } else {
    bridgeFocus(t, friend).requestFocus();
    await t.pump();
    if (source == 'menuKey') {
      await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    } else {
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.f10);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
  }
  await t.pump();
  await t.pump();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite disabled primary retains independent $source recovery',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = const Size(1200, 900);
          final semantics = t.ensureSemantics();
          var opened = 0, recovered = 0;
          final ship = find.byKey(const ValueKey('menu-tool-ship'));
          try {
            await t.pumpWidget(
              host(
                BridgePreviewDock(
                  selected: BridgePreviewPanel.execHangar,
                  openPanels: const {BridgePreviewPanel.execHangar},
                  execHangarEnabled: false,
                  onToggle: (_) => opened++,
                  onRecover: (_) => recovered++,
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await t.ensureVisible(ship);
            await t.pumpAndSettle();
            final node = exposedFriend(t, label: '行政机库', target: ship);
            expect(
              node.getSemanticsData().flagsCollection.isEnabled,
              ui.Tristate.isFalse,
            );
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            if (source == 'pointer') {
              await t.tapAt(t.getCenter(ship), buttons: kSecondaryMouseButton);
            } else if (source == 'reader') {
              final id = node
                  .getSemanticsData()
                  .customSemanticsActionIds!
                  .single;
              t.binding.performSemanticsAction(
                ui.SemanticsActionEvent(
                  type: ui.SemanticsAction.customAction,
                  viewId: t.view.viewId,
                  nodeId: node.id,
                  arguments: id,
                ),
              );
            } else {
              final focus = t
                  .widget<Focus>(
                    find
                        .descendant(
                          of: find.byKey(
                            const ValueKey('menu-context-focus-execHangar'),
                          ),
                          matching: find.byType(Focus),
                        )
                        .first,
                  )
                  .focusNode!;
              focus.requestFocus();
              await t.pump();
              expect(focus.hasFocus, isTrue);
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
              expect(opened, 0);
              await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
            }
            await t.pumpAndSettle();
            expect(find.text('移回当前屏幕'), findsOneWidget);
            if (source == 'pointer') {
              await t.tap(find.text('移回当前屏幕'));
            } else {
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
            }
            await t.pump();
            expect(recovered, 1);
            expect(opened, 0);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await detach(t);
            t.view.reset();
          }
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'menuKey', 'reader']) {
      for (final select in [false, true]) {
        testWidgets(
          '$suite $source context select=$select keeps primary and native lease',
          (t) async {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = const Size(1200, 900);
            final semantics = t.ensureSemantics();
            final baseline = nativeViewportMenus.value;
            final calls = <(String, InteractionSource)>[];
            try {
              await t.pumpWidget(
                host(
                  dock(
                    toggle: (_) => calls.add((
                      'open',
                      captureStarBridgeActivationSource()(),
                    )),
                    recover: (_) => calls.add((
                      'recover',
                      captureStarBridgeActivationSource()(),
                    )),
                  ),
                  suite,
                ),
              );
              await t.pumpAndSettle();
              await openContext(t, source);
              expect(find.text('移回当前屏幕'), findsOneWidget);
              expect(calls, isEmpty);
              expect(nativeViewportMenus.value, baseline + 1);
              if (source == 'pointer') {
                await t.pumpAndSettle();
              }
              if (select) {
                if (source == 'pointer') {
                  await t.tap(find.text('移回当前屏幕'));
                } else {
                  await t.sendKeyEvent(LogicalKeyboardKey.enter);
                }
                await t.pump();
                expect(calls, [
                  (
                    'recover',
                    source == 'pointer'
                        ? InteractionSource.pointer
                        : InteractionSource.keyboard,
                  ),
                ]);
              } else {
                await t.sendKeyEvent(LogicalKeyboardKey.escape);
                expect(calls, isEmpty);
              }
              await t.pumpAndSettle();
              expect(find.text('移回当前屏幕'), findsNothing);
              FocusManager.instance.primaryFocus?.unfocus();
              await t.pumpAndSettle();
              expect(nativeViewportMenus.value, baseline);
              final node = exposedFriend(t);
              expect(
                node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                isTrue,
              );
              t.binding.performSemanticsAction(
                ui.SemanticsActionEvent(
                  type: ui.SemanticsAction.tap,
                  viewId: t.view.viewId,
                  nodeId: node.id,
                ),
              );
              await t.pump();
              expect(calls.last, ('open', InteractionSource.keyboard));
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await detach(t);
              t.view.reset();
              expect(nativeViewportMenus.value, baseline);
            }
          },
        );
      }
    }
    for (final change in ['hidden', 'native', 'closed', 'lease', 'dispose']) {
      testWidgets('$suite open context retires on $change without recovery', (
        t,
      ) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(1200, 900);
        var shown = true, active = true, opened = true;
        Object identity = Object();
        late StateSetter update;
        var calls = 0;
        final baseline = nativeViewportMenus.value;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  TooltipVisibility(
                    visible: shown,
                    child: NativeViewportScope(
                      active: active,
                      child: BridgePreviewDock(
                        selected: opened ? BridgePreviewPanel.friends : null,
                        openPanels: opened
                            ? const {BridgePreviewPanel.friends}
                            : const {},
                        recoveryIdentities: {
                          BridgePreviewPanel.friends: identity,
                        },
                        onToggle: (_) {},
                        onRecover: (_) => calls++,
                      ),
                    ),
                  ),
                  suite,
                );
              },
            ),
          );
          await t.pumpAndSettle();
          await openContext(t, 'pointer');
          await t.pumpAndSettle();
          expect(find.text('移回当前屏幕'), findsOneWidget);
          if (change == 'dispose') {
            await detach(t);
          } else {
            update(() {
              switch (change) {
                case 'hidden':
                  shown = false;
                case 'native':
                  active = false;
                case 'closed':
                  opened = false;
                case 'lease':
                  identity = Object();
              }
            });
          }
          await t.pump();
          await t.pump();
          await t.pumpAndSettle();
          expect(find.text('移回当前屏幕'), findsNothing);
          expect(calls, 0);
          expect(nativeViewportMenus.value, baseline);
          expect(t.takeException(), isNull);
        } finally {
          await detach(t);
          t.view.reset();
          expect(nativeViewportMenus.value, baseline);
        }
      });
    }
  }
  testWidgets(
    'dock Shift F10 opens only the context action, Enter stays primary',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1200, 900);
      final primary = <BridgePreviewPanel>[],
          secondary = <BridgePreviewPanel>[];
      try {
        await t.pumpWidget(
          host(
            dock(toggle: primary.add, recover: secondary.add),
            InteractionSuite.scan,
          ),
        );
        await t.pumpAndSettle();
        bridgeFocus(t, friend).requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(primary, [BridgePreviewPanel.friends]);
        await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.f10);
        await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await t.pump();
        await t.pump();
        expect(find.text('移回当前屏幕'), findsOneWidget);
        expect(secondary, isEmpty);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(find.text('移回当前屏幕'), findsNothing);
        expect(primary, [BridgePreviewPanel.friends]);
      } finally {
        await detach(t);
        t.view.reset();
      }
    },
  );
}
