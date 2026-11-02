import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_recovery_prompt.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;

FocusNode focusOf(WidgetTester t, String choice) {
  final control = t.widget(find.byKey(Key('menu-recovery-$choice')));
  return switch (control) {
    SuitePressable(:final focusNode) => focusNode!,
    ButtonStyleButton(:final focusNode) => focusNode!,
    _ => throw StateError('Not an exposed recovery choice'),
  };
}

void main() {
  setUpAll(loadFonts);
  testWidgets('actual auxiliary recovery choices use the selected scan suite', (
    t,
  ) async {
    final choices = <String>[];
    try {
      await t.pumpWidget(
        host(MenuRecoveryPrompt(onChoose: choices.add), InteractionSuite.scan),
      );
      await t.pump();
      final actions = find.byType(SuitePressable);
      expect(actions, findsNWidgets(2));
      for (final element in actions.evaluate()) {
        expect(InteractionScope.of(element).suite, InteractionSuite.scan);
      }
      await t.tap(find.text('恢复窗口'));
      expect(choices, ['restore']);
    } finally {
      await detach(t);
    }
  });

  for (final suite in InteractionSuite.values) {
    for (final choice in ['restore', 'startClean']) {
      final id = choice == 'restore' ? 'restore' : 'start-clean';
      final label = choice == 'restore' ? '恢复窗口' : '仅打开菜单';
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets('$suite $source $choice is synchronous and source-aware', (
          t,
        ) async {
          final semantics = t.ensureSemantics();
          final choices = <String>[];
          final sources = <InteractionSource>[];
          try {
            await t.pumpWidget(
              host(
                MenuRecoveryPrompt(
                  onChoose: (value) {
                    choices.add(value);
                    sources.add(currentStarBridgeActivationSource);
                  },
                ),
                suite,
              ),
            );
            await t.pump();
            final target = find.byKey(Key('menu-recovery-$id'));
            final named = find.bySemanticsLabel(label);
            expect(named, findsOneWidget);
            final node = t.getSemantics(named);
            expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue,
            );
            if (source == 'pointer') {
              await t.tap(target);
            } else if (source == 'keyboard') {
              focusOf(t, id).requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              t.binding.performSemanticsAction(
                ui.SemanticsActionEvent(
                  type: ui.SemanticsAction.tap,
                  viewId: t.view.viewId,
                  nodeId: node.id,
                ),
              );
            }
            expect(choices, [choice]);
            expect(sources, [
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ]);
            // This view never pretends the server accepted the choice.
            await t.pump();
            expect(find.byType(MenuRecoveryPrompt), findsOneWidget);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
            await detach(t);
          }
        });
      }
    }

    testWidgets(
      '$suite busy blocks both choices without dismissing or losing failure',
      (t) async {
        final semantics = t.ensureSemantics();
        final choices = <String>[];
        try {
          await t.pumpWidget(
            host(
              MenuRecoveryPrompt(
                onChoose: choices.add,
                busy: true,
                failed: true,
              ),
              suite,
            ),
          );
          await t.pump();
          for (final id in ['restore', 'start-clean']) {
            final target = find.byKey(Key('menu-recovery-$id'));
            await t.tap(target, warnIfMissed: false);
            final node = t.getSemantics(
              find.bySemanticsLabel(id == 'restore' ? '恢复窗口' : '仅打开菜单'),
            );
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            expect(
              node.getSemanticsData().flagsCollection.isFocused,
              ui.Tristate.none,
            );
          }
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.sendKeyEvent(LogicalKeyboardKey.space);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump(const Duration(milliseconds: 80));
          expect(choices, isEmpty);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(find.text('未能确认恢复选择，请重试。原有布局仍保留。'), findsOneWidget);
        } finally {
          semantics.dispose();
          await detach(t);
        }
      },
    );

    testWidgets(
      '$suite failed choice can be retried and is never mapped to success locally',
      (t) async {
        final choices = <String>[];
        var busy = false, failed = false;
        late StateSetter update;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  MenuRecoveryPrompt(
                    onChoose: (value) {
                      choices.add(value);
                      update(() => busy = true);
                    },
                    busy: busy,
                    failed: failed,
                  ),
                  suite,
                );
              },
            ),
          );
          await t.pump();
          await t.tap(find.text('恢复窗口'));
          await t.pump();
          await t.tap(find.text('仅打开菜单'), warnIfMissed: false);
          expect(choices, ['restore']);
          update(() {
            busy = false;
            failed = true;
          });
          await t.pump();
          expect(find.text('未能确认恢复选择，请重试。原有布局仍保留。'), findsOneWidget);
          await t.tap(find.text('仅打开菜单'));
          expect(choices, ['restore', 'startClean']);
          await t.pump();
          expect(find.byType(MenuRecoveryPrompt), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          await detach(t);
        }
      },
    );

    testWidgets(
      '$suite default clean choice and keyboard traversal stay local',
      (t) async {
        final choices = <String>[];
        try {
          await t.pumpWidget(
            host(MenuRecoveryPrompt(onChoose: choices.add), suite),
          );
          await t.pump();
          await t.pump();
          expect(focusOf(t, 'start-clean').hasFocus, isTrue);
          await t.sendKeyEvent(LogicalKeyboardKey.space);
          expect(choices, ['startClean']);
          focusOf(t, 'restore').requestFocus();
          await t.pump();
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pump();
          expect(focusOf(t, 'start-clean').hasFocus, isTrue);
        } finally {
          await detach(t);
        }
      },
    );

    testWidgets(
      '$suite live style and reduce keep focus and original command contract',
      (t) async {
        final choices = <String>[];
        late StateSetter update;
        var current = suite, reduce = false;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return host(
                  MenuRecoveryPrompt(onChoose: choices.add),
                  current,
                  reduce: reduce,
                );
              },
            ),
          );
          await t.pump();
          final focus = focusOf(t, 'restore');
          focus.requestFocus();
          await t.pump();
          update(() {
            current = InteractionSuite
                .values[(suite.index + 1) % InteractionSuite.values.length];
            reduce = true;
          });
          await t.pump();
          await t.pump();
          expect(focusOf(t, 'restore'), same(focus));
          expect(focus.hasFocus, isTrue);
          final data = InteractionScope.of(
            t.element(find.byKey(const Key('menu-recovery-restore'))),
          );
          expect(data.suite, current);
          expect(data.reduceMotion, isTrue);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(choices, ['restore']);
          await t.pump();
          await t.pump(const Duration(milliseconds: 1000));
          expect(t.binding.transientCallbackCount, 0);
        } finally {
          await detach(t);
        }
      },
    );

    testWidgets('$suite outside click and escape do not choose or dismiss', (
      t,
    ) async {
      final choices = <String>[];
      try {
        await t.pumpWidget(
          host(MenuRecoveryPrompt(onChoose: choices.add), suite),
        );
        await t.pump();
        await t.tapAt(const Offset(5, 5));
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.byType(MenuRecoveryPrompt), findsOneWidget);
        expect(choices, isEmpty);
        expect(
          t.widget<ModalBarrier>(find.byType(ModalBarrier).last).dismissible,
          isFalse,
        );
      } finally {
        await detach(t);
      }
    });
  }
}
