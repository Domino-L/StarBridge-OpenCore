import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;

SemanticsNode exposed(WidgetTester t, String id) {
  var node = t.getSemantics(find.byKey(Key(id)));
  while (node.parent != null &&
      (node.isMergedIntoParent ||
          !node.getSemanticsData().hasAction(ui.SemanticsAction.tap))) {
    node = node.parent!;
  }
  return node;
}

Future<void> fire(WidgetTester t, String input, String id) async {
  final target = find.byKey(Key(id));
  await t.ensureVisible(target);
  await t.pump();
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'keyboard') {
    final widget = t.widget(target);
    final node = switch (widget) {
      SuitePressable(:final focusNode) => focusNode!,
      ButtonStyleButton(:final focusNode) => focusNode!,
      IconButton(:final focusNode) => focusNode!,
      MenuItemButton(:final focusNode) => focusNode!,
      _ => throw StateError('No public focus target'),
    };
    node.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final node = exposed(t, id);
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

Widget panel({ValueChanged<String>? action, VoidCallback? close}) =>
    TrayQuickPanel(
      state: const TrayQuickPanelState(
        runtime: TrayRuntimeState.running,
        overlay: TrayOverlayState.disabled,
      ),
      onDismiss: close ?? () {},
      onOpen: () async => action?.call('open'),
      onOverlaySettings: () async => action?.call('settings'),
      onToggleOverlay: () async => action?.call('enable'),
      onExit: () async => action?.call('exit'),
    );

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final command in ['open', 'settings', 'enable', 'exit', 'close']) {
        testWidgets(
          '$suite $input tray $command preserves exact immediate intent',
          (t) async {
            final sem = t.ensureSemantics();
            final calls = <(String, InteractionSource)>[];
            try {
              void capture(String value) =>
                  calls.add((value, currentStarBridgeActivationSource));
              await t.pumpWidget(
                scopedApp(
                  panel(action: capture, close: () => capture('close')),
                  suite,
                ),
              );
              await t.pumpAndSettle();
              await fire(t, input, 'tray-$command');
              expect(calls, [
                (
                  command,
                  input == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                ),
              ]);
              await t.pumpAndSettle();
              expect(t.takeException(), isNull);
            } finally {
              sem.dispose();
              await t.pumpWidget(const SizedBox());
              await t.pump();
            }
          },
        );
      }
    }
    for (final result in ['success', 'failure', 'dispose']) {
      testWidgets(
        '$suite pending command $result keeps guard and independent close',
        (t) async {
          final sem = t.ensureSemantics();
          final pending = Completer<void>();
          var calls = 0, closes = 0;
          try {
            await t.pumpWidget(
              scopedApp(
                TrayQuickPanel(
                  state: const TrayQuickPanelState(
                    overlay: TrayOverlayState.disabled,
                  ),
                  onDismiss: () => closes++,
                  onOpen: () async {
                    calls++;
                    await pending.future;
                  },
                  onExit: () async {},
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await fire(t, 'pointer', 'tray-open');
            await t.pump();
            expect(calls, 1);
            expect(find.text('正在处理…'), findsOneWidget);
            for (final id in ['tray-open', 'tray-exit']) {
              expect(
                t
                    .getSemantics(find.byKey(Key(id)))
                    .getSemanticsData()
                    .flagsCollection
                    .isEnabled,
                ui.Tristate.isFalse,
              );
            }
            await t.tapAt(t.getCenter(find.byKey(const Key('tray-open'))));
            await t.pump();
            expect(calls, 1);
            await fire(t, 'keyboard', 'tray-close');
            expect(closes, 1);
            expect(find.text('未开启'), findsOneWidget);
            if (result == 'dispose') {
              await t.pumpWidget(const SizedBox());
              pending.completeError(StateError('Synthetic rejected late'));
            } else if (result == 'failure') {
              pending.completeError(StateError('Synthetic rejected'));
            } else {
              pending.complete();
            }
            await t.pumpAndSettle();
            if (result == 'failure') {
              expect(find.text('未能完成操作，请重试。'), findsOneWidget);
              await fire(t, 'reader', 'tray-open');
              await t.pumpAndSettle();
              expect(calls, 2);
            }
            expect(t.takeException(), isNull);
          } finally {
            if (!pending.isCompleted) pending.complete();
            sem.dispose();
            await t.pumpWidget(const SizedBox());
            await t.pump();
          }
        },
      );
    }
  }
}
