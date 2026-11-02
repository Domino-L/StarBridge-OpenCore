import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_flutter/features/settings/general_settings_motion.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3de_flows_test.dart'
    show SettingsFixture, MotionStore, frames, motion, activate;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite $input retained-data retry keeps values and source', (
        t,
      ) async {
        final h = SettingsFixture();
        final sem = t.ensureSemantics();
        try {
          await h.mount(t, suite);
          final confirmed = h.owner.projection.value.confirmed;
          h.store.delayedRead = true;
          final failed = h.owner.retry();
          h.store.reads.single.completeError(
            const AppPreferencesStoreException(
              AppPreferencesFailure.readFailed,
            ),
          );
          await failed;
          await t.pumpAndSettle();
          expect(h.owner.projection.value.canEdit, isFalse);
          expect(
            find.byKey(const Key('general-settings-retry')),
            findsOneWidget,
          );
          await activate(t, input, 'general-settings-retry');
          await frames(t);
          expect(h.owner.projection.value.confirmed, same(confirmed));
          expect(
            find.byKey(const Key('general-appearance-light')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('general-settings-loading')),
            findsOneWidget,
          );
          expect(
            motion(t).source,
            input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          );
          expect(
            find.byType(SuiteProgressBar),
            input == 'pointer' ? findsOneWidget : findsNothing,
          );
          h.store.reads.last.complete(h.store.result());
          await t.pumpAndSettle();
          expect(h.owner.projection.value.canEdit, isTrue);
          expect(find.byKey(const Key('general-settings-retry')), findsNothing);
          expect(h.store.writes, isEmpty);
        } finally {
          sem.dispose();
          await h.close(t);
        }
      });
      for (final row in [false, true]) {
        testWidgets(
          '$suite $input switch tile=$row forwards one current source',
          (t) async {
            final sem = t.ensureSemantics();
            var value = false;
            final calls = <(bool, InteractionSource)>[];
            try {
              await t.pumpWidget(
                scopedApp(
                  StatefulBuilder(
                    builder: (_, update) {
                      void change(bool next) {
                        calls.add((next, currentStarBridgeActivationSource));
                        update(() => value = next);
                      }

                      return row
                          ? StarBridgeSwitch.tile(
                              controlKey: const Key('probe-switch'),
                              label: 'Toggle',
                              value: value,
                              onChanged: change,
                            )
                          : StarBridgeSwitch(
                              controlKey: const Key('probe-switch'),
                              label: 'Toggle',
                              value: value,
                              onChanged: change,
                            );
                    },
                  ),
                  suite,
                ),
              );
              await t.pumpAndSettle();
              final target = find.byKey(const Key('probe-switch'));
              if (input == 'pointer') {
                await t.tap(target);
              } else if (input == 'reader') {
                var node = t.getSemantics(target);
                while (!node.getSemanticsData().hasAction(
                  ui.SemanticsAction.tap,
                )) {
                  node = node.parent!;
                }
                t.binding.performSemanticsAction(
                  ui.SemanticsActionEvent(
                    type: ui.SemanticsAction.tap,
                    viewId: t.view.viewId,
                    nodeId: node.id,
                  ),
                );
              } else {
                // Traverse the actual shared target; no private state/controller calls.
                await t.sendKeyEvent(LogicalKeyboardKey.tab);
                await t.pump();
                await t.sendKeyEvent(LogicalKeyboardKey.enter);
              }
              await t.pumpAndSettle();
              expect(calls, [
                (
                  true,
                  input == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                ),
              ]);
              await t.tap(target);
              await t.pumpAndSettle();
              expect(calls.last, (false, InteractionSource.pointer));
              expect(calls, hasLength(2));
            } finally {
              sem.dispose();
              await t.pumpWidget(const SizedBox());
            }
          },
        );
      }
    }
    testWidgets('$suite newer retry survives an older wrapper finally', (
      t,
    ) async {
      final h = SettingsFixture();
      try {
        await h.mount(t, suite);
        h.store.delayedRead = true;
        final state = motion(t);
        final older = runStarBridgeActivation(
          InteractionSource.pointer,
          () => state.run(h.owner.retry),
        );
        await frames(t);
        final latest = runStarBridgeActivation(
          InteractionSource.keyboard,
          () => state.run(h.owner.retry),
        );
        await frames(t);
        h.store.reads.first.complete(h.store.result());
        expect(await older, isFalse);
        await frames(t);
        expect(state.source, InteractionSource.keyboard);
        expect(state.staticWait, isFalse);
        h.store.reads.last.complete(h.store.result());
        expect(await latest, isTrue);
        await t.pumpAndSettle();
      } finally {
        await h.close(t);
      }
    });
    testWidgets(
      '$suite external account projection retires source without changing storage source meaning',
      (t) async {
        final h = SettingsFixture();
        h.store.values = StoredAppPreferences(
          localeOverride: null,
          appearanceMode: h.store.values.appearanceMode,
          motionPreference: MotionPreference.followSystem,
        );
        try {
          await h.mount(t, suite);
          await activate(t, 'pointer', 'general-appearance-light');
          await frames(t);
          h.owner.updateAccountLocale(const Locale('zh', 'TW'));
          await frames(t);
          expect(motion(t).source, InteractionSource.programmatic);
          expect(motion(t).staticWait, isTrue);
          expect(h.owner.projection.value.source, AppPreferencesSource.stored);
          expect(
            h.owner.projection.value.operation,
            AppPreferencesOperation.saving,
          );
          h.store.accept();
          await t.pumpAndSettle();
          expect(h.owner.projection.value.revision, 5);
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets('$suite early Future completion is not a projection receipt', (
      t,
    ) async {
      final h = SettingsFixture();
      try {
        await h.mount(t, suite);
        final state = motion(t);
        Future<bool>? ownerWork;
        final ui = runStarBridgeActivation(
          InteractionSource.pointer,
          () => state.run(() {
            ownerWork = h.owner.setLocale(const Locale('en', 'US'));
            return Future.value(true); // Deliberately premature implementation.
          }),
        );
        expect(await ui, isTrue);
        await frames(t);
        expect(
          h.owner.projection.value.operation,
          AppPreferencesOperation.saving,
        );
        expect(
          find.byKey(const Key('general-settings-saving')),
          findsOneWidget,
        );
        expect(state.staticWait, isTrue);
        expect(find.byType(SuiteProgressBar), findsNothing);
        h.store.accept();
        await ownerWork;
        await t.pumpAndSettle();
      } finally {
        await h.close(t);
      }
    });
    testWidgets(
      '$suite synchronous throw retires changed pending source without swallowing error',
      (t) async {
        final h = SettingsFixture();
        try {
          await h.mount(t, suite);
          Future<bool>? pending;
          await expectLater(
            runStarBridgeActivation(
              InteractionSource.pointer,
              () => motion(t).run(() {
                pending = h.owner.setLocale(const Locale('en', 'US'));
                throw StateError('synthetic synchronous throw');
              }),
            ),
            throwsStateError,
          );
          await frames(t);
          expect(motion(t).staticWait, isTrue);
          h.store.accept();
          await pending;
          await t.pumpAndSettle();
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets(
      '$suite keyboard opening is not reused for later external attach',
      (t) async {
        size(t, const Size(1400, 1100));
        final owner = AppPreferencesModule();
        final first = MotionStore()..delayedRead = true;
        final read = owner.attachStore(first);
        final next = MotionStore()..delayedRead = true;
        try {
          await t.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) => starBridgeInitialReadViewport(
                  context,
                  source: InteractionSource.keyboard,
                  child: GeneralSettingsPage(preferences: owner),
                ),
              ),
              suite,
            ),
          );
          await frames(t);
          expect(motion(t).source, InteractionSource.keyboard);
          expect(find.byType(SuiteProgressBar), findsNothing);
          first.reads.single.complete(first.result());
          await read;
          await t.pumpAndSettle();
          final newer = owner.attachStore(next);
          await frames(t);
          expect(motion(t).source, InteractionSource.programmatic);
          expect(motion(t).staticWait, isTrue);
          expect(
            find.byKey(const Key('general-appearance-light')),
            findsOneWidget,
          );
          next.reads.single.complete(next.result());
          await newer;
          await t.pumpAndSettle();
        } finally {
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
    testWidgets(
      '$suite leaving pending preference preserves Owner and ignores disposed UI completion',
      (t) async {
        final h = SettingsFixture();
        try {
          await h.mount(t, suite);
          await activate(t, 'keyboard', 'general-language-control-en-US');
          await frames(t);
          await t.pumpWidget(scopedApp(const SizedBox(), suite));
          await t.pump();
          h.store.accept();
          await t.pump();
          await t.pumpWidget(h.page(suite));
          await t.pumpAndSettle();
          expect(
            h.owner.projection.value.confirmed!.localeOverride,
            const Locale('en', 'US'),
          );
          expect(h.store.writes, hasLength(1));
          expect(find.byType(GeneralSettingsWaiting), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
    );
  }
}
