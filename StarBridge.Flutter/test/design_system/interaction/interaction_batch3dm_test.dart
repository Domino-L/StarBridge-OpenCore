import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_motion_controls.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_page.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_save_bar.dart';
import 'package:starbridge_flutter/features/tools/tools_page.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3aa_test.dart' show reader;
import 'interaction_batch3b_test.dart' show exposedNodes;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/tools/exec_hangar_presets.dart';
import '../../features/tools/exec_hangar_test.dart' as original;

Future<void> act(
  WidgetTester t,
  Finder target,
  String source,
  String label,
) async {
  await t.ensureVisible(target);
  if (source == 'reader') {
    reader(t, label);
    return;
  }
  if (source == 'pointer') {
    await t.tap(target);
    return;
  }
  var owned = find.descendant(
    of: target,
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton || w is SuitePressable,
    ),
  );
  if (t.widget(target) is ButtonStyleButton ||
      t.widget(target) is SuitePressable) {
    owned = target;
  }
  final widget = t.widget(owned.first);
  final focus = switch (widget) {
    ButtonStyleButton b => b.focusNode!,
    SuitePressable b =>
      b.focusNode ??
          t
              .widget<FocusableActionDetector>(
                find
                    .descendant(
                      of: owned.first,
                      matching: find.byType(FocusableActionDetector),
                    )
                    .first,
              )
              .focusNode!,
    _ => throw StateError('missing focus'),
  };
  focus.requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
}

class DeferredPort extends original.Port {
  Completer<ExecHangarSnapshot>? pendingSave;
  final submitted = <({ExecHangarReminders rules, int revision})>[];
  @override
  Future<ExecHangarSnapshot> save(ExecHangarReminders rules, int revision) {
    submitted.add((rules: rules, revision: revision));
    return pendingSave?.future ?? super.save(rules, revision);
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source save bar preserves callbacks, source and busy/conflict gates',
        (t) async {
          final semantics = t.ensureSemantics();
          size(t, const Size(900, 700));
          final received = <InteractionSource>[];
          var resets = 0;
          Widget page({bool busy = false, bool conflict = false}) => scopedApp(
            ExecHangarSaveBar(
              busy: busy,
              conflict: conflict,
              onSave: () => received.add(captureStarBridgeActivationSource()()),
              onReset: () => resets++,
            ),
            suite,
          );
          await t.pumpWidget(page());
          await t.pumpAndSettle();
          await act(t, find.byKey(const Key('exec-save')), source, '保存提醒设置');
          await t.pumpAndSettle();
          expect(received, [
            source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          ]);
          if (source == 'pointer') {
            for (var i = 0; i < 4; i++) {
              await t.tap(find.byKey(const Key('exec-save')));
              await t.pump(const Duration(milliseconds: 40));
            }
            expect(received.length, 5);
          }
          await t.pumpWidget(page(conflict: true));
          await t.pumpAndSettle();
          final save = find.ancestor(
            of: find.byKey(const Key('exec-save')),
            matching: find.byType(StarBridgeActionButton),
          );
          expect(t.widget<StarBridgeActionButton>(save).onActivate, isNull);
          await t.tap(find.text('撤销修改'));
          await t.pumpAndSettle();
          expect(resets, 1);
          await t.pumpWidget(page(busy: true));
          await t.pumpAndSettle();
          expect(find.byType(ExecHangarMotionButton), findsNWidgets(2));
          for (final action in t.widgetList<StarBridgeActionButton>(
            find.byType(StarBridgeActionButton),
          )) {
            expect(action.onActivate, isNull);
          }
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
      testWidgets(
        '$suite $source real tool save keeps draft on failure and confirmed result alone clears it',
        (t) async {
          final semantics = t.ensureSemantics();
          size(t, const Size(1440, 1200));
          final port = DeferredPort();
          await t.pumpWidget(scopedApp(ExecHangarPage(port: port), suite));
          await t.pumpAndSettle();
          await pickExecPreset(t, execBeforeOpen, 15);
          port.pendingSave = Completer();
          await act(t, find.byKey(const Key('exec-save')), source, '保存提醒设置');
          await t.pump();
          expect(port.submitted, hasLength(1));
          expect(port.submitted.single.rules.beforeOpenMinutes, 15);
          expect(port.submitted.single.revision, 0);
          expect(port.starts, 0);
          port.pendingSave!.completeError(StateError('synthetic refusal'));
          await t.pumpAndSettle();
          expect(execPresetShown(t, execBeforeOpen), 15);
          expect(find.byType(ExecHangarSaveBar), findsOneWidget);
          expect(port.starts, 0);
          port.pendingSave = null;
          await act(t, find.byKey(const Key('exec-save')), source, '保存提醒设置');
          await t.pumpAndSettle();
          expect(port.snapshot.reminders.beforeOpenMinutes, 15);
          expect(port.submitted, hasLength(2));
          expect(port.snapshot.revision, 1);
          expect(find.byType(ExecHangarSaveBar), findsNothing);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
          expect(t.takeException(), isNull);
        },
      );
      testWidgets(
        '$suite $source dirty leave dialog preserves decisions and keyboard exit',
        (t) async {
          final semantics = t.ensureSemantics();
          size(t, const Size(1440, 1200));
          final port = DeferredPort();
          final key = GlobalKey<ExecHangarPageState>();
          await t.pumpWidget(
            scopedApp(ExecHangarPage(key: key, port: port), suite),
          );
          await t.pumpAndSettle();
          await pickExecPreset(t, execBeforeOpen, 20);
          bool? result;
          unawaited(
            runStarBridgeActivation<void>(
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
              () async {
                result = await key.currentState!.confirmLeave(
                  key.currentContext!,
                );
              },
            ),
          );
          await t.pumpAndSettle();
          final dialogContext = t.element(find.byType(AlertDialog));
          expect(
            ModalRoute.of(dialogContext),
            isA<StarBridgeDialogRoute<bool>>(),
          );
          expect(
            (ModalRoute.of(
              dialogContext,
            ) as StarBridgeDialogRoute<bool>).instant,
            source != 'pointer',
          );
          final stay = find.ancestor(
            of: find.text('继续编辑'),
            matching: find.byType(ExecHangarMotionButton),
          );
          await act(t, stay, source, '继续编辑');
          await t.pumpAndSettle();
          expect(result, isFalse);
          expect(port.submitted, isEmpty);
          expect(find.byType(ExecHangarSaveBar), findsOneWidget);
          unawaited(
            key.currentState!
                .confirmLeave(key.currentContext!)
                .then((value) => result = value),
          );
          await t.pumpAndSettle();
          final discard = find.ancestor(
            of: find.text('放弃并离开'),
            matching: find.byType(ExecHangarMotionButton),
          );
          await act(t, discard, source, '放弃并离开');
          await t.pumpAndSettle();
          expect(result, isTrue);
          expect(port.submitted, isEmpty);
          expect(port.starts, 0);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
          expect(t.takeException(), isNull);
        },
      );
      testWidgets(
        '$suite $source real tool entry forwards exact destination and activation',
        (t) async {
          final semantics = t.ensureSemantics();
          size(t, const Size(900, 900));
          final targets = <String>[];
          final sources = <InteractionSource>[];
          await t.pumpWidget(
            scopedApp(
              Actions(
                actions: {
                  OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                    onInvoke: (intent) {
                      targets.add(intent.route);
                      sources.add(captureStarBridgeActivationSource()());
                      return null;
                    },
                  ),
                },
                child: const ToolsPage(),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          final card = find.byKey(const Key('tool-exec-hangar'));
          if (source == 'reader') {
            final nodes = exposedNodes(t)
                .where(
                  (n) =>
                      n.getSemanticsData().label.contains('行政机库') &&
                      n.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                )
                .toList();
            expect(nodes, hasLength(1));
            t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
              nodes.single.id,
              ui.SemanticsAction.tap,
            );
          } else {
            await act(t, card, source, '');
          }
          await t.pumpAndSettle();
          expect(targets, ['/tools/exec-hangar']);
          expect(sources, [
            source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          ]);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
    }
  }
}
