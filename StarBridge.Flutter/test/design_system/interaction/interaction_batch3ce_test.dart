import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/overlay_settings/in_memory_overlay_settings_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_feature.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';

import 'interaction_batch3ca_test.dart' show MenuFixture, key;
import 'interaction_batch3bz_test.dart' show WorkspacePort;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3i_test.dart' show scopedApp;

class LeavePort extends WorkspacePort {
  bool fail = false;
  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    // Commands activated through Semantics run in another framework zone.
    // Check the invariant without a guarded WidgetTester.expect in that zone.
    if (expectedRevision != revision) throw StateError('Unexpected revision');
    writes.add((mutation, currentStarBridgeActivationSource));
    await pending?.future;
    if (fail) {
      return const OverlayWorkspaceWriteResult.failed(
        OverlaySettingsFailure.writeFailed,
      );
    }
    if (reject) {
      return OverlayWorkspaceWriteResult.failed(
        OverlaySettingsFailure.writeConflict,
      );
    }
    values = mutation.settings ?? values;
    geometry = mutation.layout ?? geometry;
    revision++;
    return OverlayWorkspaceWriteResult.completed(snapshot);
  }
}

class Fixture {
  final menu = MenuFixture(), port = LeavePort();
  late final module = OverlaySettingsModule(
    InMemoryOverlaySettingsAdapter(),
    workspacePort: port,
  );
  bool? result;
  InteractionSource? finalSource;
  int completions = 0;
  Future<void> ready({bool menuDirty = false, bool infoDirty = false}) async {
    await menu.load();
    if (!menuDirty) menu.draft.discard();
    module.menuDraft = menu.draft;
    await module.workspace!.initialize();
    if (infoDirty) {
      // Edits save on their own; leaving only asks about a save that failed.
      // The store keeps failing, so leaving's own retry fails too and asks.
      port.fail = true;
      module.workspace!.updateSetting('showNotice', false);
      await module.workspace!.save();
      port.writes.clear();
    }
  }

  /// After the information prompt appeared: forget the retry leaving made
  /// before asking, and let the store recover for the user's choice.
  void prompted() {
    port.writes.clear();
    port.fail = false;
  }

  Future<void> clean(WidgetTester t) async {
    for (final pending in [port.pending, menu.port.pending]) {
      if (pending != null && !pending.isCompleted) pending.complete();
    }
    await frames(t);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    module.dispose();
  }
}

class Harness extends StatefulWidget {
  const Harness(this.f, this.suite, {super.key});
  final Fixture f;
  final InteractionSuite suite;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  bool reduce = false, light = false, visible = true, localScope = false;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    StarBridgeInteractionConfiguration(
      suite: widget.suite,
      reduceMotion: reduce,
      child: visible
          ? Builder(
              builder: (context) => Center(
                child: StarBridgeActionButton(
                  controlKey: const Key('leave'),
                  onActivate: (source) {
                    unawaited(
                      runStarBridgeActivation(source, () async {
                        widget.f.result = await confirmOverlayWorkspaceLeave(
                          context,
                          widget.f.module,
                        );
                        widget.f.finalSource =
                            currentStarBridgeActivationSource;
                        widget.f.completions++;
                      }),
                    );
                  },
                  child: const Text('Leave'),
                ),
              ),
            )
          : const SizedBox(),
    ),
    localScope ? InteractionSuite.standard : widget.suite,
    reduce: localScope ? false : reduce,
    light: light,
  );
}

Future<HarnessState> mount(
  WidgetTester t,
  Fixture f,
  InteractionSuite suite,
) async {
  final k = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(f, suite, key: k));
  await frames(t);
  return k.currentState!;
}

InteractionSource expected(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final menu in [false, true]) {
      for (final reject in [false, true]) {
        testWidgets(
          '$suite menu=$menu pending reply reject=$reject after opener removed',
          (t) async {
            final f = Fixture();
            await f.ready(menuDirty: menu, infoDirty: !menu);
            if (menu) f.menu.additional.changeResume(true);
            final pending = Completer<void>();
            if (menu) f.menu.port.pending = pending;
            final h = await mount(t, f, suite);
            await key(t, 'pointer', 'leave');
            await frames(t);
            if (!menu) {
              f.prompted();
              f.port.pending = pending;
              f.port.reject = reject;
            }
            await key(
              t,
              'pointer',
              '${menu ? 'menu' : 'overlay'}-unsaved-leave-save',
            );
            await frames(t);
            expect(f.result, isNull);
            h.change(() => h.visible = false);
            await t.pump();
            if (menu && reject) {
              pending.completeError(StateError('Synthetic refusal'));
            } else {
              pending.complete();
            }
            await frames(t);
            expect(f.result, false);
            expect(f.completions, 1);
            expect(
              menu
                  ? f.menu.draft.dirty
                  : f.module.workspace!.projection.value.dirty,
              reject,
            );
            await f.clean(t);
          },
        );
      }
      testWidgets(
        '$suite menu=$menu busy save cannot be discarded by leaving',
        (t) async {
          final f = Fixture();
          await f.ready(menuDirty: menu, infoDirty: !menu);
          if (menu) f.menu.additional.changeResume(true);
          final pending = Completer<void>();
          if (menu) {
            f.menu.port.pending = pending;
          } else {
            f.prompted();
            f.port.pending = pending;
          }
          final save = menu ? f.menu.draft.save() : f.module.workspace!.save();
          await mount(t, f, suite);
          await key(t, 'pointer', 'leave');
          await frames(t);
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            menu
                ? f.menu.draft.dirty
                : f.module.workspace!.projection.value.dirty,
            true,
          );
          // Menu refuses at once; information waits for the running save.
          expect(f.result, menu ? false : isNull);
          pending.complete();
          await frames(t);
          expect(await save, true);
          expect(f.result, menu ? false : true);
          await f.clean(t);
        },
      );
      testWidgets('$suite menu=$menu prompt opener unmounted preserves draft', (
        t,
      ) async {
        final f = Fixture();
        await f.ready(menuDirty: menu, infoDirty: !menu);
        final h = await mount(t, f, suite);
        await key(t, 'pointer', 'leave');
        await frames(t);
        h.change(() => h.visible = false);
        await t.pump();
        await key(
          t,
          'pointer',
          '${menu ? 'menu' : 'overlay'}-unsaved-leave-discard',
        );
        await frames(t);
        expect(f.result, false);
        expect(
          menu
              ? f.menu.draft.dirty
              : f.module.workspace!.projection.value.dirty,
          true,
        );
        await f.clean(t);
      });
    }
    testWidgets('$suite replaced menu draft cannot receive old discard', (
      t,
    ) async {
      final f = Fixture();
      await f.ready(menuDirty: true);
      final replacement = MenuFixture();
      await replacement.load();
      await mount(t, f, suite);
      await key(t, 'pointer', 'leave');
      await frames(t);
      f.module.menuDraft = replacement.draft;
      await key(t, 'pointer', 'menu-unsaved-leave-discard');
      await frames(t);
      expect(f.result, false);
      expect(f.menu.draft.dirty, true);
      expect(replacement.draft.dirty, true);
      expect(f.menu.port.sources, isEmpty);
      expect(replacement.port.sources, isEmpty);
      f.module.menuDraft = f.menu.draft;
      replacement.draft.dispose();
      await f.clean(t);
    });
    testWidgets(
      '$suite passive runtime refresh does not invalidate leave confirmation',
      (t) async {
        final f = Fixture();
        await f.ready(infoDirty: true);
        await mount(t, f, suite);
        await key(t, 'pointer', 'leave');
        await frames(t);
        f.prompted();
        await f.module.workspace!.refreshRuntime('zh-CN');
        await key(t, 'keyboard', 'overlay-unsaved-leave-save');
        await frames(t);
        expect(f.result, true);
        expect(f.port.writes, hasLength(1));
        await f.clean(t);
      },
    );
    testWidgets('$suite local suite reaches both confirmation levels', (
      t,
    ) async {
      final f = Fixture();
      await f.ready(menuDirty: true);
      final h = await mount(t, f, suite);
      h.change(() => h.localScope = true);
      await frames(t);
      await key(t, 'pointer', 'leave');
      await frames(t);
      final save = find
          .descendant(
            of: find.byKey(const Key('menu-unsaved-leave-save')),
            matching: find.byType(Text),
          )
          .first;
      expect(InteractionScope.of(t.element(save)).suite, suite);
      await key(t, 'pointer', 'menu-unsaved-leave-save');
      await frames(t);
      final confirm = find
          .descendant(
            of: find.byKey(const Key('menu-clear-memory-confirm')),
            matching: find.byType(Text),
          )
          .first;
      expect(InteractionScope.of(t.element(confirm)).suite, suite);
      h.change(() => h.reduce = true);
      await t.pump();
      await t.pump();
      expect(InteractionScope.of(t.element(confirm)).reduceMotion, true);
      await key(t, 'keyboard', 'menu-clear-memory-cancel');
      await frames(t);
      expect(f.result, false);
      expect(f.menu.port.sources, isEmpty);
      await f.clean(t);
    });
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final menu in [false, true]) {
        for (final choice in ['cancel', 'discard', 'save']) {
          testWidgets(
            '$suite $input ${menu ? 'menu' : 'information'} $choice',
            (t) async {
              final semantics = t.ensureSemantics();
              final f = Fixture();
              await f.ready(menuDirty: menu, infoDirty: !menu);
              // Keep the nested confirmation in separate tests below.
              if (menu) f.menu.additional.changeResume(true);
              await mount(t, f, suite);
              await key(t, input, 'leave');
              await frames(t);
              final prefix = menu ? 'menu' : 'overlay';
              final route = ModalRoute.of(
                t.element(find.byKey(Key('$prefix-unsaved-leave-dialog'))),
              );
              expect(route, isA<StarBridgeDialogRoute>());
              expect(
                (route! as StarBridgeDialogRoute).barrierDismissible,
                false,
              );
              expect(f.result, isNull);
              if (!menu) f.prompted();
              await key(t, input, '$prefix-unsaved-leave-$choice');
              await frames(t);
              expect(f.completions, 1);
              expect(f.result, choice != 'cancel');
              expect(f.finalSource, expected(input));
              expect(
                menu
                    ? f.menu.draft.dirty
                    : f.module.workspace!.projection.value.dirty,
                choice == 'cancel',
              );
              expect(
                f.menu.port.sources.length + f.port.writes.length,
                choice == 'save' ? 1 : 0,
              );
              if (choice == 'save') {
                expect(
                  menu ? f.menu.port.sources.single : f.port.writes.single.$2,
                  expected(input),
                );
              }
              semantics.dispose();
              await f.clean(t);
            },
          );
        }
      }

      for (final reject in [false, true]) {
        testWidgets('$suite $input information pending actual reply $reject', (
          t,
        ) async {
          final semantics = t.ensureSemantics();
          final f = Fixture();
          await f.ready(infoDirty: true);
          await mount(t, f, suite);
          await key(t, input, 'leave');
          await frames(t);
          f.prompted();
          f.port.pending = Completer();
          f.port.reject = reject;
          await key(t, input, 'overlay-unsaved-leave-save');
          await frames(t);
          expect(f.result, isNull);
          expect(f.port.writes, hasLength(1));
          expect(f.module.workspace!.projection.value.dirty, true);
          f.port.pending!.complete();
          await frames(t);
          expect(f.result, !reject);
          expect(f.module.workspace!.projection.value.dirty, reject);
          semantics.dispose();
          await f.clean(t);
        });
      }

      testWidgets('$suite $input both dirty preserve Menu then information', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        final f = Fixture();
        await f.ready(menuDirty: true, infoDirty: true);
        await mount(t, f, suite);
        await key(t, input, 'leave');
        await frames(t);
        expect(
          find.byKey(const Key('overlay-unsaved-leave-dialog')),
          findsNothing,
        );
        await key(t, input, 'menu-unsaved-leave-discard');
        await frames(t);
        expect(f.result, isNull);
        expect(f.menu.draft.dirty, false);
        await key(t, input, 'overlay-unsaved-leave-cancel');
        await frames(t);
        expect(f.result, false);
        expect(f.module.workspace!.projection.value.dirty, true);
        semantics.dispose();
        await f.clean(t);
      });
    }

    for (final menu in [false, true]) {
      for (final undo in [false, true]) {
        testWidgets(
          '$suite ${menu ? 'menu' : 'information'} changed while prompt undo=$undo',
          (t) async {
            final f = Fixture();
            await f.ready(menuDirty: menu, infoDirty: !menu);
            await mount(t, f, suite);
            await key(t, 'pointer', 'leave');
            await frames(t);
            f.port.writes.clear();
            if (menu) {
              f.menu.draft.change({'showMembers': false});
              if (undo) f.menu.draft.undo();
            } else {
              f.module.workspace!.updateSetting('showNotice', true);
              if (undo) f.module.workspace!.undo();
            }
            await key(
              t,
              'pointer',
              '${menu ? 'menu' : 'overlay'}-unsaved-leave-discard',
            );
            await frames(t);
            expect(f.result, false);
            expect(f.menu.port.sources, isEmpty);
            // An information change tried to save on its own (the store
            // still fails); leaving's discard never ran.
            expect(f.port.writes, hasLength(menu ? 0 : 1));
            if (menu || undo) {
              expect(
                menu
                    ? f.menu.draft.dirty
                    : f.module.workspace!.projection.value.dirty,
                true,
              );
            }
            await f.clean(t);
          },
        );
      }
    }

    testWidgets(
      '$suite mixed confirmation sources reach real nested save and caller',
      (t) async {
        final f = Fixture();
        await f.ready(menuDirty: true, infoDirty: true);
        await mount(t, f, suite);
        await key(t, 'pointer', 'leave');
        await frames(t);
        await key(t, 'keyboard', 'menu-unsaved-leave-save');
        await frames(t);
        expect(f.menu.port.sources, isEmpty);
        expect(
          find.byKey(const Key('menu-clear-memory-confirm')),
          findsOneWidget,
        );
        await key(t, 'pointer', 'menu-clear-memory-confirm');
        await frames(t);
        expect(f.menu.port.sources.single, InteractionSource.pointer);
        expect(f.menu.resume.sources.single, InteractionSource.pointer);
        f.prompted();
        await key(t, 'keyboard', 'overlay-unsaved-leave-save');
        await frames(t);
        expect(f.result, true);
        expect(f.finalSource, InteractionSource.keyboard);
        expect(f.port.writes.single.$2, InteractionSource.keyboard);
        await f.clean(t);
      },
    );

    for (final partial in [false, true]) {
      testWidgets(
        '$suite menu additional ${partial ? 'partial rejection' : 'success'}',
        (t) async {
          final f = Fixture();
          await f.ready(menuDirty: true, infoDirty: true);
          f.menu.resume.fail = partial;
          await mount(t, f, suite);
          await key(t, 'pointer', 'leave');
          await frames(t);
          await key(t, 'pointer', 'menu-unsaved-leave-save');
          await frames(t);
          await key(t, 'pointer', 'menu-clear-memory-confirm');
          await frames(t);
          expect(f.menu.port.sources, hasLength(1));
          expect(f.menu.resume.sources, hasLength(1));
          if (partial) {
            expect(f.result, false);
            expect(f.menu.draft.dirty, true);
            expect(
              find.byKey(const Key('overlay-unsaved-leave-dialog')),
              findsNothing,
            );
          } else {
            expect(f.result, isNull);
            await key(t, 'pointer', 'overlay-unsaved-leave-discard');
            await frames(t);
            expect(f.result, true);
          }
          // Success reaches the information guard, whose one retry fails.
          expect(f.port.writes, hasLength(partial ? 0 : 1));
          await f.clean(t);
        },
      );
    }

    testWidgets('$suite nested memory prompt rejects changed draft', (t) async {
      final f = Fixture();
      await f.ready(menuDirty: true);
      await mount(t, f, suite);
      await key(t, 'pointer', 'leave');
      await frames(t);
      await key(t, 'pointer', 'menu-unsaved-leave-save');
      await frames(t);
      f.menu.draft.change({'showClock': true});
      await key(t, 'pointer', 'menu-clear-memory-confirm');
      await frames(t);
      expect(f.result, false);
      expect(f.menu.draft.dirty, true);
      expect(f.menu.port.sources, isEmpty);
      expect(f.menu.resume.sources, isEmpty);
      await f.clean(t);
    });

    testWidgets('$suite live settings while confirmation open', (t) async {
      final f = Fixture();
      await f.ready(infoDirty: true);
      final h = await mount(t, f, suite);
      await key(t, 'pointer', 'leave');
      await t.pump(const Duration(milliseconds: 50));
      h.change(() {
        h.reduce = true;
        h.light = true;
      });
      await t.pump();
      await t.pump();
      final context = t.element(
        find.byKey(const Key('overlay-unsaved-leave-dialog')),
      );
      expect(InteractionScope.of(context).reduceMotion, true);
      expect(Theme.of(context).brightness, Brightness.light);
      expect(
        (ModalRoute.of(context)! as StarBridgeDialogRoute).animation!.value,
        1,
      );
      await key(t, 'keyboard', 'overlay-unsaved-leave-cancel');
      await t.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(f.result, false);
      await f.clean(t);
    });

    testWidgets(
      '$suite menu becomes dirty during information save blocks leave',
      (t) async {
        final f = Fixture();
        await f.ready(infoDirty: true);
        await mount(t, f, suite);
        await key(t, 'pointer', 'leave');
        await frames(t);
        f.prompted();
        f.port.pending = Completer();
        await key(t, 'pointer', 'overlay-unsaved-leave-save');
        await frames(t);
        f.menu.draft.change({'showClock': false});
        f.port.pending!.complete();
        await frames(t);
        expect(f.result, false);
        expect(f.menu.draft.dirty, true);
        expect(f.module.workspace!.projection.value.dirty, false);
        await f.clean(t);
      },
    );
  }
}
