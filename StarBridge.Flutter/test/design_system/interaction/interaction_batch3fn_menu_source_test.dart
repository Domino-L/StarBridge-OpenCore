import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

class SourceMenuProbe {
  SourceMenuProbe(this.suite, {this.contextMenu = false});
  InteractionSuite suite;
  final bool contextMenu;
  bool enabled = true, reduce = false, light = false, hook = true;
  int primary = 0;
  final events = <String>[];
  late MenuController controller;
  late FocusNode focus;
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, state) {
      update = state;
      return scopedApp(
        StarBridgeMenuAnchor(
          semanticLabel: 'Fixture menu',
          contextMenu: contextMenu,
          enabled: enabled,
          onOpen: () => events.add('legacy'),
          onOpenWithSource: hook
              ? (source) => events.add('source:${source.name}')
              : null,
          onClose: () => events.add('close'),
          entries: [
            StarBridgeMenuEntry(
              id: 'only',
              label: 'Fixture action',
              child: const Text('Fixture action'),
              onActivate: (source) => events.add('action:${source.name}'),
            ),
          ],
          builder: (context, menu, node, toggle) {
            controller = menu;
            focus = node;
            if (contextMenu) {
              return GestureDetector(
                excludeFromSemantics: true,
                onSecondaryTapDown: (_) => toggle(InteractionSource.pointer),
                child: TextButton(
                  key: const Key('source-menu-trigger'),
                  focusNode: node,
                  onPressed: () => primary++,
                  child: const Text('Primary'),
                ),
              );
            }
            return StarBridgeActionRow(
              controlKey: const Key('source-menu-trigger'),
              focusNode: node,
              onActivate: enabled ? (_, source) => toggle(source) : null,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Open fixture menu'),
              ),
            );
          },
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<void> sourceMenuFrames(WidgetTester t, {bool settle = false}) async {
  await t.pump();
  await t.pump();
  if (settle) {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> tabToSourceMenu(WidgetTester t, SourceMenuProbe p) async {
  final target = find.byKey(const Key('source-menu-trigger'));
  FocusScope.of(t.element(target)).unfocus();
  await sourceMenuFrames(t);
  for (var i = 0; !p.focus.hasPrimaryFocus && i < 20; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await sourceMenuFrames(t);
  }
  expect(
    p.focus.hasPrimaryFocus,
    isTrue,
    reason: '${p.focus}\n${FocusManager.instance.toStringDeep()}',
  );
}

Future<void> openSourceMenu(
  WidgetTester t,
  SourceMenuProbe p,
  String input,
) async {
  final target = find.byKey(const Key('source-menu-trigger'));
  if (input == 'reader') {
    final nodes = exposedNodes(t).where((n) {
      final d = n.getSemanticsData();
      if (p.contextMenu) {
        return d.customSemanticsActionIds?.any(
              (id) =>
                  CustomSemanticsAction.getAction(id)?.label == 'Fixture menu',
            ) ==
            true;
      }
      return d.flagsCollection.isButton &&
          d.label == 'Fixture menu' &&
          d.hasAction(ui.SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1));
    if (p.contextMenu) {
      final id = nodes.single
          .getSemanticsData()
          .customSemanticsActionIds!
          .singleWhere(
            (id) =>
                CustomSemanticsAction.getAction(id)?.label == 'Fixture menu',
          );
      t.binding.performSemanticsAction(
        ui.SemanticsActionEvent(
          type: ui.SemanticsAction.customAction,
          viewId: t.view.viewId,
          nodeId: nodes.single.id,
          arguments: id,
        ),
      );
    } else {
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        nodes.single.id,
        ui.SemanticsAction.tap,
      );
    }
  } else if (input == 'keyboard') {
    await tabToSourceMenu(t, p);
    if (p.contextMenu) {
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.f10);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    } else {
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
    }
  } else if (p.contextMenu) {
    await t.tap(target, buttons: kSecondaryMouseButton);
  } else {
    final touch = await t.startGesture(
      t.getCenter(target),
      kind: ui.PointerDeviceKind.touch,
    );
    await touch.up();
  }
  await sourceMenuFrames(t);
}

Future<void> readerSourceAction(WidgetTester t) async {
  final nodes = exposedNodes(t).where((n) {
    final d = n.getSemanticsData();
    return d.flagsCollection.isButton &&
        d.label == 'Fixture action' &&
        d.hasAction(ui.SemanticsAction.tap);
  }).toList();
  expect(nodes, hasLength(1));
  t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    nodes.single.id,
    ui.SemanticsAction.tap,
  );
  await sourceMenuFrames(t, settle: true);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final contextMenu in [false, true]) {
        testWidgets(
          '3fn $suite $input contextual=$contextMenu source callbacks once in order',
          (t) async {
            size(t, const Size(900, 700));
            final semantics = t.ensureSemantics();
            final p = SourceMenuProbe(suite, contextMenu: contextMenu);
            try {
              await t.pumpWidget(p.app());
              await sourceMenuFrames(t);
              await openSourceMenu(t, p, input);
              final source = input == 'pointer' ? 'pointer' : 'keyboard';
              expect(p.events, ['legacy', 'source:$source']);
              expect(p.controller.isOpen, isTrue);
              expect(
                p.primary,
                0,
                reason: 'Context menu never consumes primary activation as a command',
              );
              p.update(() {
                p.reduce = true;
                p.light = true;
              });
              await sourceMenuFrames(t);
              expect(p.events, ['legacy', 'source:$source']);
              await readerSourceAction(t);
              expect(p.events, [
                'legacy',
                'source:$source',
                'close',
                'action:keyboard',
              ]);
              expect(p.controller.isOpen, isFalse);
              // Direct controller use has no proven origin, even after a real
              // pointer/keyboard open or an assistive menu-row command.
              p.controller.open();
              await sourceMenuFrames(t);
              expect(p.events.sublist(4), ['legacy', 'source:programmatic']);
              p.controller.close();
              await sourceMenuFrames(t, settle: true);
              expect(p.events.sublist(4), [
                'legacy',
                'source:programmatic',
                'close',
              ]);
              p.controller.open();
              await sourceMenuFrames(t);
              expect(p.events.sublist(7), ['legacy', 'source:programmatic']);
              p.controller.close();
              await sourceMenuFrames(t, settle: true);
              expect(p.events.where((e) => e == 'legacy').length, 3);
              expect(p.events.where((e) => e == 'close').length, 3);
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              semantics.dispose();
            }
          },
        );
      }
    }

    testWidgets(
      '3fn $suite absent new hook preserves old lifecycle and disabled gates',
      (t) async {
        size(t, const Size(900, 700));
        final semantics = t.ensureSemantics();
        final p = SourceMenuProbe(suite)..hook = false;
        try {
          await t.pumpWidget(p.app());
          await sourceMenuFrames(t);
          await openSourceMenu(t, p, 'reader');
          expect(p.events, ['legacy']);
          await readerSourceAction(t);
          expect(p.events, ['legacy', 'close', 'action:keyboard']);
          p.update(() => p.enabled = false);
          await sourceMenuFrames(t);
          p.controller.open();
          await sourceMenuFrames(t, settle: true);
          expect(p.controller.isOpen, isFalse);
          await t.tapAt(
            t.getCenter(find.byKey(const Key('source-menu-trigger'))),
          );
          await sourceMenuFrames(t);
          expect(p.events, ['legacy', 'close', 'action:keyboard']);
          expect(
            exposedNodes(t).where(
              (n) =>
                  n.getSemanticsData().label == 'Fixture menu' &&
                  n.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            ),
            isEmpty,
          );
          p.update(() {
            p.enabled = true;
            p.hook = true;
          });
          await sourceMenuFrames(t);
          p.controller.open();
          await sourceMenuFrames(t);
          expect(p.events.sublist(3), ['legacy', 'source:programmatic']);
          p.controller.close();
          await sourceMenuFrames(t, settle: true);
          expect(p.events.sublist(3), [
            'legacy',
            'source:programmatic',
            'close',
          ]);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      },
    );
  }
}
