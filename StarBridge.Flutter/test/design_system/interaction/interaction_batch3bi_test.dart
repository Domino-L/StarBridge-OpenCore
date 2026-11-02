import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_panel.dart';

import '../../features/gameplay_time/gameplay_time_test.dart' show Harness;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bg_test.dart' show activate;

Future<void> input(WidgetTester t, String source, Key key) async {
  final target = find.byKey(key);
  await t.ensureVisible(target);
  await t.pump();
  final switchTarget = find.ancestor(
    of: target,
    matching: find.byType(StarBridgeSwitch),
  );
  if (source == 'pointer' && switchTarget.evaluate().isNotEmpty) {
    await t.tapAt(t.getCenter(target));
    await t.pump();
    await t.pump();
  } else if (source == 'keyboard' && switchTarget.evaluate().isNotEmpty) {
    final pressable = find.descendant(
      of: switchTarget.first,
      matching: find.byType(SuitePressable),
    );
    expect(pressable, findsOneWidget);
    final focus = t.widget<SuitePressable>(pressable).focusNode!;
    expect(focus.canRequestFocus, isTrue);
    focus.requestFocus();
    await t.pump();
    expect(FocusManager.instance.primaryFocus, same(focus));
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    await t.pump();
  } else {
    await activate(t, source, key);
  }
}

Future<void> showPanel(
  WidgetTester t,
  Harness h,
  InteractionSuite suite,
) async {
  await t.pumpWidget(
    scopedApp(
      SingleChildScrollView(child: GameplayTimePanel(controller: h.controller)),
      suite,
    ),
  );
  await t.pumpAndSettle();
}

Future<void> close(WidgetTester t, Harness h) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  await h.close(t);
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite rejected history keeps exact preview for explicit retry',
      (t) async {
        final h = Harness();
        try {
          await showPanel(t, h, suite);
          await input(t, 'pointer', const Key('gameplay-history-import'));
          await t.pumpAndSettle();
          final preview = h.controller.value.preview!;
          h.confirmResult = 'unavailable';
          await input(t, 'keyboard', const Key('gameplay-history-confirm'));
          await t.pumpAndSettle();
          expect(h.controller.value.preview, same(preview));
          expect(h.controller.value.historyError, 'unavailable');
          await t.pump(const Duration(seconds: 2));
          expect(
            h.requests.where((r) => r.name == 'gameplayTime.historyConfirm'),
            hasLength(1),
          );
          h.confirmResult = 'imported';
          await input(t, 'pointer', const Key('gameplay-history-confirm'));
          await t.pumpAndSettle();
          final ids = h.requests
              .where((r) => r.name == 'gameplayTime.historyConfirm')
              .map((r) => r.payload['previewId']);
          expect(ids, [preview.id, preview.id]);
          expect(
            find.byKey(const Key('gameplay-history-preview')),
            findsNothing,
          );
        } finally {
          await close(t, h);
        }
      },
    );
    testWidgets('$suite account change retires only its held history dialog', (
      t,
    ) async {
      final h = Harness();
      try {
        await showPanel(t, h, suite);
        await input(t, 'pointer', const Key('gameplay-history-import'));
        await t.pumpAndSettle();
        h.holdNames.add('gameplayTime.historyConfirm');
        await input(t, 'keyboard', const Key('gameplay-history-confirm'));
        final old = h.held!;
        h.holdNames.clear();
        h.changeAccount();
        await t.pump();
        await t.pumpAndSettle();
        expect(find.byKey(const Key('gameplay-history-preview')), findsNothing);
        h.respond(old);
        await t.pump();
        await t.pumpAndSettle();
        expect(h.controller.value.historyState, isNot('imported'));
        expect(find.byType(GameplayTimePanel), findsOneWidget);
      } finally {
        await close(t, h);
      }
    });
    testWidgets('$suite gameplay panel uses shared interaction controls', (
      t,
    ) async {
      final h = Harness(resetSupported: true);
      try {
        await t.pumpWidget(
          scopedApp(
            SingleChildScrollView(
              child: GameplayTimePanel(controller: h.controller),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(StarBridgeSwitch), findsNWidgets(2));
        expect(find.byType(StarBridgeActionButton), findsNWidgets(3));
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        await h.close(t);
      }
    });
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source import then keyboard confirm stops both waiting decorations',
        (t) async {
          final h = Harness();
          final semantics = t.ensureSemantics();
          try {
            await showPanel(t, h, suite);
            await input(t, source, const Key('gameplay-history-import'));
            await t.pumpAndSettle();
            h.holdNames.add('gameplayTime.historyConfirm');
            await input(t, 'keyboard', const Key('gameplay-history-confirm'));
            expect(find.byType(SuiteProgressBar), findsNWidgets(2));
            for (final element in find.byType(SuiteProgressBar).evaluate()) {
              expect(InteractionScope.of(element).reduceMotion, isTrue);
            }
            h.holdNames.clear();
            h.respond(h.held!);
            await t.pump();
            await t.pumpAndSettle();
          } finally {
            await close(t, h);
            semantics.dispose();
          }
        },
      );
      // Each branch below drives the real controller and its bridge receipts.
      testWidgets(
        '$suite $source consent waits for original receipt with static keyboard wait',
        (t) async {
          final semantics = t.ensureSemantics();
          final h = Harness();
          try {
            await showPanel(t, h, suite);
            h.holdNames.add('gameplayTime.setConsent');
            await input(t, source, const Key('gameplay-time-record-switch'));
            expect(h.controller.value.busy, isTrue);
            expect(h.controller.value.consent, 'allowed');
            expect(
              h.requests
                  .where((r) => r.name == 'gameplayTime.setConsent')
                  .length,
              1,
            );
            final progress = find.byType(SuiteProgressBar);
            expect(progress, findsOneWidget);
            expect(
              InteractionScope.of(t.element(progress)).reduceMotion,
              source != 'pointer',
            );
            await t.pump(const Duration(milliseconds: 300));
            expect(t.binding.hasScheduledFrame, source == 'pointer');
            h.holdNames.clear();
            h.respond(h.held!);
            await t.pump();
            await t.pumpAndSettle();
            expect(h.controller.value.consent, 'declined');
          } finally {
            await close(t, h);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source reset cancel and confirm preserve destructive owner',
        (t) async {
          final semantics = t.ensureSemantics();
          final h = Harness(resetSupported: true);
          try {
            await showPanel(t, h, suite);
            await input(t, source, const Key('gameplay-reset-open'));
            await t.pump();
            await t.pump();
            final dialog = find.byKey(const Key('gameplay-reset-confirmation'));
            expect(dialog, findsOneWidget);
            final route =
                ModalRoute.of(t.element(dialog))!
                    as StarBridgeDialogRoute<bool>;
            expect(route.instant, source != 'pointer');
            await t.pump(const Duration(milliseconds: 300));
            await input(t, source, const Key('gameplay-reset-keep'));
            await t.pumpAndSettle();
            expect(
              h.requests.where((r) => r.name == 'gameplayTime.resetConfirm'),
              isEmpty,
            );
            await input(t, source, const Key('gameplay-reset-open'));
            await t.pumpAndSettle();
            await input(t, source, const Key('gameplay-reset-confirm'));
            await t.pumpAndSettle();
            expect(
              h.requests.where((r) => r.name == 'gameplayTime.resetConfirm'),
              hasLength(1),
            );
            expect(find.byType(GameplayTimePanel), findsOneWidget);
          } finally {
            await close(t, h);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source history preview confirms once and keeps disabled controls while busy',
        (t) async {
          final semantics = t.ensureSemantics();
          final h = Harness();
          try {
            await showPanel(t, h, suite);
            await input(t, source, const Key('gameplay-history-import'));
            await t.pumpAndSettle();
            final dialog = find.byKey(const Key('gameplay-history-preview'));
            expect(dialog, findsOneWidget);
            expect(
              (ModalRoute.of(t.element(dialog))! as StarBridgeDialogRoute<void>)
                  .instant,
              source != 'pointer',
            );
            h.holdNames.add('gameplayTime.historyConfirm');
            await input(t, source, const Key('gameplay-history-confirm'));
            expect(h.controller.value.busy, isTrue);
            final buttons = t.widgetList<StarBridgeActionButton>(
              find.descendant(
                of: dialog,
                matching: find.byType(StarBridgeActionButton),
              ),
            );
            expect(buttons.every((b) => b.onActivate == null), isTrue);
            final progress = find.descendant(
              of: dialog,
              matching: find.byType(SuiteProgressBar),
            );
            expect(
              InteractionScope.of(t.element(progress)).reduceMotion,
              source != 'pointer',
            );
            expect(
              h.requests.where((r) => r.name == 'gameplayTime.historyConfirm'),
              hasLength(1),
            );
            h.holdNames.clear();
            h.respond(h.held!);
            await t.pump();
            await t.pumpAndSettle();
            expect(
              find.byKey(const Key('gameplay-history-preview')),
              findsNothing,
            );
            expect(h.controller.value.historyState, 'imported');
          } finally {
            await close(t, h);
            semantics.dispose();
          }
        },
      );
    }
  }
}
