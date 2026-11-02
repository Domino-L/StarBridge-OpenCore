import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_port.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/routing/exit_application_intent.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_flutter/features/settings/general_settings_motion.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3dc_actions_test.dart' show hitRow;
import 'interaction_batch3i_test.dart' show scopedApp;

class MotionStore implements AppPreferencesStore {
  StoredAppPreferences values = const StoredAppPreferences(
    localeOverride: Locale('zh', 'CN'),
    appearanceMode: AppearanceMode.dark,
    motionPreference: MotionPreference.followSystem,
  );
  int revision = 4;
  bool delayedRead = false, disposed = false;
  final reads = <Completer<AppPreferencesReadResult>>[];
  final writes = <Completer<AppPreferencesReadResult>>[];
  final patches = <AppPreferencesPatch>[];
  final expected = <int>[];
  AppPreferencesReadResult result({
    AppPreferencesSource source = AppPreferencesSource.stored,
  }) => AppPreferencesReadResult(
    values: values,
    revision: revision,
    source: source,
  );
  @override
  Future<AppPreferencesReadResult> read() {
    if (!delayedRead) return Future.value(result());
    final read = Completer<AppPreferencesReadResult>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<AppPreferencesReadResult> update(
    AppPreferencesPatch patch, {
    required int expectedRevision,
  }) {
    patches.add(patch);
    expected.add(expectedRevision);
    final write = Completer<AppPreferencesReadResult>();
    writes.add(write);
    return write.future;
  }

  void accept() {
    values = values.apply(patches.last);
    revision++;
    writes.last.complete(result());
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class SettingsFixture {
  final owner = AppPreferencesModule();
  final store = MotionStore();
  final exits = <ExitApplicationIntent>[];
  final gate = Completer<void>();
  Widget page(InteractionSuite suite, {bool reduce = false}) => scopedApp(
    Actions(
      actions: {
        ExitApplicationIntent: CallbackAction<ExitApplicationIntent>(
          onInvoke: (intent) {
            exits.add(intent);
            return null;
          },
        ),
      },
      child: GeneralSettingsPage(preferences: owner),
    ),
    suite,
    reduce: reduce,
  );
  Future<void> mount(WidgetTester t, InteractionSuite suite) async {
    size(t, const Size(1400, 1100));
    await owner.attachStore(store);
    await t.pumpWidget(page(suite));
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    owner.dispose();
  }
}

Future<void> frames(WidgetTester t) async {
  await t.pump();
  await t.pump();
  await t.pump(const Duration(milliseconds: 160));
}

GeneralSettingsMotionState motion(WidgetTester t) =>
    t.state(find.byType(GeneralSettingsMotion));
Future<void> activate(WidgetTester t, String input, String id) async {
  final target = find.byKey(Key(id));
  await t.ensureVisible(target);
  await t.pump();
  if (id.startsWith('general-language-control') ||
      id.startsWith('general-appearance')) {
    return hitRow(t, input, id);
  }
  if (input == 'keyboard') {
    final control = t.widget(target);
    if (control is Switch || control is SuiteSwitch) {
      final focus = control is Switch
          ? control.focusNode!
          : (control as SuiteSwitch).focusNode!;
      focus.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      return;
    }
  }
  if (input == 'reader') {
    var node = t.getSemantics(target);
    while (!node.getSemanticsData().hasAction(ui.SemanticsAction.tap)) {
      node = node.parent!;
    }
    t.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        viewId: t.view.viewId,
        nodeId: node.id,
      ),
    );
    return;
  }
  await fire(t, input, id);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final id in [
        'general-language-control-zh-CN',
        'general-language-control-zh-TW',
        'general-language-control-en-US',
        'general-appearance-dark',
        'general-appearance-light',
        'general-reduce-motion',
      ]) {
        testWidgets(
          '$suite $input $id preserves optimistic preview and exact confirmed receipt',
          (t) async {
            final h = SettingsFixture();
            final sem = t.ensureSemantics();
            try {
              await h.mount(t, suite);
              final old = h.owner.projection.value.confirmed;
              await activate(t, input, id);
              await frames(t);
              expect(h.store.writes, hasLength(1));
              expect(h.store.expected, [4]);
              expect(
                h.owner.projection.value.operation,
                AppPreferencesOperation.saving,
              );
              expect(h.owner.projection.value.confirmed, same(old));
              expect(h.owner.projection.value.revision, 4);
              expect(
                motion(t).source,
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(
                find.byKey(const Key('general-settings-saving')),
                findsOneWidget,
              );
              expect(
                find.byType(SuiteProgressBar),
                input == 'pointer' ? findsOneWidget : findsNothing,
              );
              expect(
                await h.owner.setLocale(const Locale('en', 'US')),
                isFalse,
              );
              expect(h.store.writes, hasLength(1));
              h.store.accept();
              await t.pumpAndSettle();
              expect(h.owner.projection.value.confirmed, same(h.store.values));
              expect(h.owner.projection.value.revision, 5);
              expect(h.owner.projection.value.canEdit, isTrue);
              expect(
                find.byKey(const Key('general-settings-saving')),
                findsNothing,
              );
              expect(t.takeException(), isNull);
            } finally {
              sem.dispose();
              await h.close(t);
            }
          },
        );
      }
      for (final id in [
        'general-language-control-en-US',
        'general-appearance-light',
        'general-reduce-motion',
      ]) {
        testWidgets(
          '$suite $input $id failed write rolls back without declaring success',
          (t) async {
            final h = SettingsFixture();
            final sem = t.ensureSemantics();
            try {
              await h.mount(t, suite);
              final old = h.owner.projection.value.confirmed;
              await activate(t, input, id);
              await frames(t);
              h.store.writes.single.completeError(
                const AppPreferencesStoreException(
                  AppPreferencesFailure.saveFailed,
                ),
              );
              await t.pumpAndSettle();
              expect(h.owner.projection.value.confirmed, same(old));
              expect(h.owner.projection.value.revision, 4);
              expect(
                h.owner.projection.value.effective.locale,
                const Locale('zh', 'CN'),
              );
              expect(
                h.owner.projection.value.effective.appearanceMode,
                AppearanceMode.dark,
              );
              expect(
                h.owner.projection.value.effective.motionPreference,
                MotionPreference.followSystem,
              );
              expect(
                h.owner.projection.value.failure,
                AppPreferencesFailure.saveFailed,
              );
              expect(find.byType(GeneralSettingsWaiting), findsNothing);
            } finally {
              sem.dispose();
              await h.close(t);
            }
          },
        );
      }
      testWidgets(
        '$suite $input exit stays independent while saving and delegates origin',
        (t) async {
          final h = SettingsFixture();
          final sem = t.ensureSemantics();
          try {
            await h.mount(t, suite);
            await activate(t, 'pointer', 'general-appearance-light');
            await frames(t);
            await activate(t, input, 'general-exit-application');
            await t.pump();
            expect(h.exits, hasLength(1));
            final origin = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            expect(h.exits.single.source, origin);
            InteractionSource? delayed;
            final guard = h.exits.single.runWithSource(() async {
              await h.gate.future;
              delayed = currentStarBridgeActivationSource;
            });
            h.gate.complete();
            await guard;
            expect(delayed, origin);
            expect(h.store.writes, hasLength(1));
            h.store.accept();
            await t.pumpAndSettle();
          } finally {
            sem.dispose();
            await h.close(t);
          }
        },
      );
    }
    testWidgets('$suite presentation noop cannot steal pending source', (
      t,
    ) async {
      final h = SettingsFixture();
      try {
        await h.mount(t, suite);
        await activate(t, 'keyboard', 'general-appearance-light');
        await frames(t);
        final state = motion(t);
        final result = await runStarBridgeActivation(
          InteractionSource.pointer,
          () => state.run(() => h.owner.setAppearanceMode(AppearanceMode.dark)),
        );
        expect(result, isFalse);
        expect(state.source, InteractionSource.keyboard);
        expect(h.store.writes, hasLength(1));
        h.store.accept();
        await t.pumpAndSettle();
      } finally {
        await h.close(t);
      }
    });
    testWidgets(
      '$suite external attach during save retires origin and old result',
      (t) async {
        final h = SettingsFixture();
        final newer = MotionStore()..delayedRead = true;
        try {
          await h.mount(t, suite);
          await activate(t, 'keyboard', 'general-appearance-light');
          await frames(t);
          final attached = h.owner.attachStore(newer);
          await frames(t);
          expect(motion(t).source, InteractionSource.programmatic);
          expect(motion(t).staticWait, isTrue);
          expect(
            find.byKey(const Key('general-settings-loading')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('general-appearance-light')),
            findsOneWidget,
          );
          h.store.accept();
          await frames(t);
          expect(h.owner.projection.value.phase, AppPreferencesPhase.loading);
          newer.reads.single.complete(newer.result());
          await attached;
          await t.pumpAndSettle();
          expect(h.owner.projection.value.confirmed, same(newer.values));
          expect(
            h.owner.projection.value.effective.appearanceMode,
            AppearanceMode.dark,
          );
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets(
      '$suite conflict rereads through original owner without extra write',
      (t) async {
        final h = SettingsFixture();
        try {
          await h.mount(t, suite);
          await activate(t, 'pointer', 'general-appearance-light');
          await frames(t);
          h.store.delayedRead = true;
          h.store.writes.single.completeError(
            const AppPreferencesStoreException(
              AppPreferencesFailure.revisionConflict,
            ),
          );
          await frames(t);
          expect(h.store.reads, hasLength(1));
          expect(h.store.writes, hasLength(1));
          h.store.revision = 9;
          h.store.reads.single.complete(h.store.result());
          await t.pumpAndSettle();
          expect(
            h.owner.projection.value.failure,
            AppPreferencesFailure.revisionConflict,
          );
          expect(h.owner.projection.value.revision, 9);
          expect(h.owner.projection.value.canEdit, isTrue);
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets(
      '$suite old page Port finally cannot clear new Port operation',
      (t) async {
        size(t, const Size(1400, 1100));
        final old = AppPreferencesModule(), newer = AppPreferencesModule();
        final oldStore = MotionStore(), newStore = MotionStore();
        await old.attachStore(oldStore);
        await newer.attachStore(newStore);
        final selected = ValueNotifier<AppPreferencesPort>(old);
        try {
          await t.pumpWidget(
            ValueListenableBuilder<AppPreferencesPort>(
              valueListenable: selected,
              builder: (_, port, _) =>
                  scopedApp(GeneralSettingsPage(preferences: port), suite),
            ),
          );
          await t.pumpAndSettle();
          await activate(t, 'pointer', 'general-appearance-light');
          await frames(t);
          selected.value = newer;
          await t.pumpAndSettle();
          await activate(t, 'keyboard', 'general-language-control-en-US');
          await frames(t);
          oldStore.accept();
          await frames(t);
          expect(motion(t).source, InteractionSource.keyboard);
          expect(
            newer.projection.value.operation,
            AppPreferencesOperation.saving,
          );
          newStore.accept();
          await t.pumpAndSettle();
          expect(
            newer.projection.value.effective.locale,
            const Locale('en', 'US'),
          );
        } finally {
          await t.pumpWidget(const SizedBox());
          selected.dispose();
          old.dispose();
          newer.dispose();
        }
      },
    );
    testWidgets(
      '$suite InMemory synchronous completion never invents waiting',
      (t) async {
        size(t, const Size(1400, 1100));
        final owner = InMemoryAppPreferences();
        try {
          await t.pumpWidget(
            scopedApp(GeneralSettingsPage(preferences: owner), suite),
          );
          await t.pumpAndSettle();
          await activate(t, 'pointer', 'general-language-control-en-US');
          await t.pumpAndSettle();
          expect(find.byType(GeneralSettingsWaiting), findsNothing);
          expect(motion(t).source, InteractionSource.programmatic);
          expect(
            owner.projection.value.effective.locale,
            const Locale('en', 'US'),
          );
        } finally {
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
  }
}
