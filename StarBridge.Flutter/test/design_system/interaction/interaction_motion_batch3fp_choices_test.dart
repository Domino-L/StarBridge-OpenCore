import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_navigation.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch2_test.dart' show pixels;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

const choiceIds = ['a', 'b', 'locked1', 'locked2', 'plain'];
const choiceLabels = [
  'First choice',
  'Second choice',
  'Locked one',
  'Locked two',
  'No hint',
];
const choiceHints = [
  'First complete explanation',
  'Second full explanation',
  'Unavailable until an existing owner allows this section',
  'Another unavailable section with a different complete reason',
  '',
];

class ChoicesProbe {
  ChoicesProbe(this.suite);
  InteractionSuite suite;
  bool reduce = false, light = false, enabled = true, accept = true;
  String selected = 'a';
  int escaped = 0;
  final before = FocusNode(), after = FocusNode();
  final boundary = GlobalKey();
  final calls = <(String, InteractionSource)>[];
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, state) {
      update = state;
      return scopedApp(
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () => escaped++,
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                focusNode: before,
                onPressed: () {},
                child: const Text('Before choices'),
              ),
              RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: 900,
                  child: StarBridgeChoiceNavigation(
                    choices: [
                      for (var i = 0; i < choiceIds.length; i++)
                        StarBridgeNavigationChoice(
                          id: choiceIds[i],
                          label: choiceLabels[i],
                          hint: choiceHints[i],
                          enabled:
                              enabled && !choiceIds[i].startsWith('locked'),
                          controlKey: ValueKey('3fp-${choiceIds[i]}'),
                          child: Text(choiceLabels[i]),
                        ),
                    ],
                    selected: selected,
                    onSelected: (id) {
                      calls.add((id, currentStarBridgeActivationSource));
                      if (accept) update(() => selected = id);
                    },
                  ),
                ),
              ),
              TextButton(
                focusNode: after,
                onPressed: () {},
                child: const Text('After choices'),
              ),
            ],
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    before.dispose();
    after.dispose();
  }
}

Future<void> choiceFrames(WidgetTester t, {bool settle = false}) async {
  await t.pump();
  await t.pump();
  if (settle) {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
}

Finder choiceTarget(String id) => find.byKey(ValueKey('3fp-$id'));
Finder choiceHint(String message) => find.byWidgetPredicate(
  (w) => w is StarBridgeTooltip && w.message == message,
);
SuiteTooltipState choiceHintState(WidgetTester t, String message) => t.state(
  find.descendant(of: choiceHint(message), matching: find.byType(SuiteTooltip)),
);
SuiteSelectionTrackState choiceTrack(WidgetTester t) =>
    t.state<SuiteSelectionTrackState>(find.byType(SuiteSelectionTrack));
FocusNode choiceFocus(WidgetTester t, String id) {
  final control = t.widget(choiceTarget(id));
  return control is ChoiceChip
      ? control.focusNode!
      : (control as SuitePressable).focusNode!;
}

void expectChoiceHints(WidgetTester t) {
  final nodes = exposedNodes(t);
  final details = nodes
      .map((n) {
        final d = n.getSemanticsData();
        return '${n.id}: label=${d.label}; hint=${d.hint}; tooltip=${d.tooltip}; '
            'tap=${d.hasAction(ui.SemanticsAction.tap)}';
      })
      .join('\n');
  for (var i = 0; i < choiceIds.length; i++) {
    final targets = nodes
        .where((n) => n.getSemanticsData().label == choiceLabels[i])
        .toList();
    expect(targets, hasLength(1), reason: details);
    final d = targets.single.getSemanticsData();
    expect(d.flagsCollection.isButton, isTrue);
    if (choiceIds[i].startsWith('locked')) {
      expect(d.hasAction(ui.SemanticsAction.tap), isFalse);
    }
    if (choiceHints[i].isEmpty) {
      expect(
        find.ancestor(
          of: choiceTarget(choiceIds[i]),
          matching: find.byType(StarBridgeTooltip),
        ),
        findsNothing,
      );
      continue;
    }
    final pattern = RegExp(RegExp.escape(choiceHints[i]));
    final carriers = nodes
        .map((node) {
          final data = node.getSemanticsData();
          final count = [data.label, data.hint, data.tooltip]
              .map((text) => pattern.allMatches(text).length)
              .reduce((a, b) => a > b ? a : b);
          return (node, count);
        })
        .where((entry) => entry.$2 > 0)
        .toList();
    expect(
      carriers,
      hasLength(1),
      reason: 'Complete hint must have one exposed carrier.\n$details',
    );
    expect(carriers.single.$2, 1, reason: details);
    expect(
      carriers.single.$1.getSemanticsData().hasAction(
        ui.SemanticsAction.longPress,
      ),
      isFalse,
    );
  }
}

Future<void> tabToChoice(WidgetTester t, String id) async {
  final target = choiceTarget(id);
  final focus = choiceFocus(t, id);
  FocusScope.of(t.element(target)).unfocus();
  await choiceFrames(t);
  for (var i = 0; !focus.hasPrimaryFocus && i < 25; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await choiceFrames(t);
  }
  expect(
    focus.hasPrimaryFocus,
    isTrue,
    reason: '$focus\n${FocusManager.instance.toStringDeep()}',
  );
}

Future<void> activateChoice(WidgetTester t, String id, String input) async {
  if (input == 'reader') {
    final label = choiceLabels[choiceIds.indexOf(id)];
    final nodes = exposedNodes(t).where((n) {
      final d = n.getSemanticsData();
      return d.flagsCollection.isButton &&
          d.label == label &&
          d.hasAction(ui.SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      ui.SemanticsAction.tap,
    );
  } else if (input == 'keyboard') {
    await tabToChoice(t, id);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final touch = await t.startGesture(
      t.getCenter(choiceTarget(id)),
      kind: ui.PointerDeviceKind.touch,
    );
    await touch.up();
  }
  await choiceFrames(t);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (var index = 0; index < 4; index++) {
      for (final input in ['hover', 'touch']) {
        testWidgets(
          '3fp $suite ${choiceIds[index]} $input tooltip leaves original action contract',
          (t) async {
            size(t, const Size(1200, 800));
            final semantics = t.ensureSemantics();
            final p = ChoicesProbe(suite);
            TestGesture? mouse;
            try {
              await t.pumpWidget(p.app());
              await choiceFrames(t, settle: true);
              final message = choiceHints[index];
              final adapter = t.widget<StarBridgeTooltip>(choiceHint(message));
              expect(adapter.consumeEscape, isFalse);
              expectChoiceHints(t);
              final bounds = t.getRect(choiceTarget(choiceIds[index]));
              if (input == 'hover') {
                mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
                await mouse.addPointer(location: const Offset(1, 1));
                await mouse.moveTo(t.getCenter(choiceTarget(choiceIds[index])));
                await t.pump(const Duration(milliseconds: 500));
              } else {
                final touch = await t.startGesture(
                  t.getCenter(choiceTarget(choiceIds[index])),
                  kind: ui.PointerDeviceKind.touch,
                );
                await t.pump(const Duration(milliseconds: 600));
                await touch.up();
              }
              await t.pump(const Duration(milliseconds: 200));
              expect(choiceHintState(t, message).isShowing, isTrue);
              expect(
                p.calls,
                isEmpty,
                reason: 'Hint exploration never selects, including unavailable choices',
              );
              expect(p.selected, 'a');
              expect(t.getRect(choiceTarget(choiceIds[index])), bounds);
              expectChoiceHints(t);
              p.update(() {
                p.reduce = true;
                p.light = true;
              });
              await choiceFrames(t);
              expect(choiceHintState(t, message).isShowing, isTrue);
              final opacity = t.widget<Opacity>(
                find.descendant(
                  of: choiceHint(message),
                  matching: find.byType(Opacity),
                ),
              );
              expect(opacity.opacity, 1);
              expect(p.calls, isEmpty);
              expectChoiceHints(t);
              expect(t.takeException(), isNull);
            } finally {
              await mouse?.removePointer();
              await p.close(t);
              semantics.dispose();
            }
          },
        );
      }
    }

    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3fp $suite $input selection is owner-confirmed with original disabled gate',
        (t) async {
          size(t, const Size(1200, 800));
          final semantics = t.ensureSemantics();
          final p = ChoicesProbe(suite)..accept = false;
          try {
            await t.pumpWidget(p.app());
            await choiceFrames(t, settle: true);
            final source = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            await activateChoice(t, 'b', input);
            expect(p.calls, [('b', source)]);
            expect(p.selected, 'a');
            expect(choiceTrack(t).indicatorRect, choiceTrack(t).itemRect(0));
            p.update(() => p.selected = 'b');
            await choiceFrames(t);
            if (input != 'pointer') {
              expect(choiceTrack(t).indicatorRect, choiceTrack(t).itemRect(1));
              expect(
                choiceTrack(t).isStretching ||
                    choiceTrack(t).isSweeping ||
                    choiceTrack(t).isRinging,
                isFalse,
              );
            }
            p.update(() {
              p.accept = true;
              p.reduce = true;
              p.light = true;
            });
            await choiceFrames(t);
            await activateChoice(t, 'plain', input);
            expect(p.calls, [('b', source), ('plain', source)]);
            expect(choiceTrack(t).indicatorRect, choiceTrack(t).itemRect(4));
            expect(
              choiceTrack(t).isStretching ||
                  choiceTrack(t).isSweeping ||
                  choiceTrack(t).isRinging,
              isFalse,
            );
            p.update(() => p.enabled = false);
            await choiceFrames(t);
            final before = p.calls.length;
            for (final id in choiceIds) {
              await t.tapAt(t.getCenter(choiceTarget(id)));
            }
            await choiceFrames(t);
            expect(p.calls.length, before);
            expect(
              exposedNodes(t).where(
                (n) =>
                    choiceLabels.contains(n.getSemanticsData().label) &&
                    n.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              ),
              isEmpty,
            );
            expectChoiceHints(t);
            expect(t.takeException(), isNull);
          } finally {
            await p.close(t);
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '3fp $suite keyboard hint is instant and Esc reaches original parent',
      (t) async {
        size(t, const Size(1200, 800));
        final semantics = t.ensureSemantics();
        final p = ChoicesProbe(suite);
        try {
          await t.pumpWidget(p.app());
          await choiceFrames(t, settle: true);
          await tabToChoice(t, 'b');
          expect(choiceHintState(t, choiceHints[1]).isShowing, isTrue);
          final opacity = t.widget<Opacity>(
            find.descendant(
              of: choiceHint(choiceHints[1]),
              matching: find.byType(Opacity),
            ),
          );
          expect(opacity.opacity, 1);
          expect(p.calls, isEmpty);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await choiceFrames(t);
          expect(p.escaped, 1);
          expect(choiceHintState(t, choiceHints[1]).isShowing, isFalse);
          expect(choiceFocus(t, 'b').hasPrimaryFocus, isTrue);
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await choiceFrames(t);
          expect(
            choiceFocus(t, 'plain').hasPrimaryFocus,
            isTrue,
            reason: 'Disabled hinted choices remain skipped by real traversal',
          );
          expect(p.calls, isEmpty);
          expectChoiceHints(t);
          expect(t.takeException(), isNull);
        } finally {
          await p.close(t);
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '3fp $suite current presses and rapid reversals retain actual feedback',
      (t) async {
        size(t, const Size(1200, 800));
        final p = ChoicesProbe(suite);
        try {
          await t.pumpWidget(p.app());
          await choiceFrames(t, settle: true);
          final idle = await pixels(t, p.boundary);
          final pointer = await t.startGesture(
            t.getCenter(choiceTarget('a')),
            kind: ui.PointerDeviceKind.touch,
          );
          // The SDK waits for its tap-down deadline before reporting a press.
          // Begin the animation on a rendered frame after that deadline, then
          // measure 80 ms into it; keep the hold below the long-press timeout.
          await t.pump(const Duration(milliseconds: 100));
          await t.pump();
          await t.pump(const Duration(milliseconds: 80));
          expect(
            await pixels(t, p.boundary),
            isNot(idle),
            reason: 'An active press must still be perceptible',
          );
          await pointer.up();
          await choiceFrames(t);
          for (final id in ['b', 'a', 'b', 'a']) {
            await t.tap(choiceTarget(id));
            await t.pump();
            await t.pump(const Duration(milliseconds: 20));
          }
          expect(p.calls, [
            for (final id in ['a', 'b', 'a', 'b', 'a'])
              (id, InteractionSource.pointer),
          ]);
          final track = choiceTrack(t);
          expect(
            track.isStretching || track.isSweeping || track.isRinging,
            suite != InteractionSuite.standard,
            reason:
                'Rapid active selection must not enter passive-data coalescing',
          );
          await choiceFrames(t, settle: true);
          expect(track.indicatorRect, track.itemRect(0));
          expect(p.selected, 'a');
          expect(t.takeException(), isNull);
        } finally {
          await p.close(t);
        }
      },
    );
  }
}
