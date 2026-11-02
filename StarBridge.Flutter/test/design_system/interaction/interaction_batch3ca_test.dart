import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_save_bar.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_editor_tools.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_inspector.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_workspace.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_additional_settings_draft.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_resume.dart';

import 'interaction_batch3bz_test.dart' show FullFixture;
import 'interaction_batch3x_test.dart' show readyPreferences;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;

Future<void> fire(WidgetTester t, String input, Finder target) async {
  await t.ensureVisible(target);
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'reader') {
    var node = t.getSemantics(target);
    if (!node.getSemanticsData().hasAction(ui.SemanticsAction.tap)) {
      final descendants = find.descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.onTap != null,
        ),
      );
      if (descendants.evaluate().isNotEmpty) {
        node = t.getSemantics(descendants.first);
      }
    }
    if (!node.getSemanticsData().hasAction(ui.SemanticsAction.tap)) {
      final readerTarget = find.ancestor(
        of: target,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.onTap != null,
        ),
      );
      if (readerTarget.evaluate().isNotEmpty) {
        node = t.getSemantics(readerTarget.first);
      }
    }
    while (!node.getSemanticsData().hasAction(ui.SemanticsAction.tap) &&
        node.parent != null) {
      node = node.parent!;
    }
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    final excluded = find.descendant(
      of: target,
      matching: find.byType(ExcludeFocus),
    );
    final text = find.descendant(of: target, matching: find.byType(Text));
    final icon = find.descendant(
      of: target,
      matching: find.byType(StarBridgeIcon),
    );
    final paint = find.descendant(
      of: target,
      matching: find.byType(CustomPaint),
    );
    final anchor = excluded.evaluate().isNotEmpty
        ? excluded.first
        : text.evaluate().isNotEmpty
        ? text.first
        : icon.evaluate().isNotEmpty
        ? icon.first
        : paint.evaluate().isNotEmpty
        ? paint.first
        : target;
    final rows = find.ancestor(
      of: target,
      matching: find.byType(SuitePressable),
    );
    final targetControl = t.widget(target);
    final rowFocus =
        targetControl is SuitePressable && targetControl.focusNode != null
        ? targetControl.focusNode
        : rows.evaluate().isEmpty
        ? null
        : t.widget<SuitePressable>(rows.first).focusNode;
    if (rowFocus != null) {
      expect(rowFocus.canRequestFocus, isTrue);
      rowFocus.requestFocus();
    } else {
      Focus.of(t.element(anchor)).requestFocus();
    }
    await t.pump();
    if (rowFocus != null) {
      expect(FocusManager.instance.primaryFocus, same(rowFocus));
    }
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await t.pump();
  await t.pump();
}

Future<void> key(WidgetTester t, String input, String key) =>
    fire(t, input, find.byKey(Key(key)));

class MenuPort implements MenuWindowPreferencesPort {
  var value = readyPreferences();
  final sources = <InteractionSource>[];
  Completer<void>? pending;
  @override
  Future<MenuWindowPreferences> read() async => value;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences next) async {
    sources.add(currentStarBridgeActivationSource);
    await pending?.future;
    return value = MenuWindowPreferences(
      next.revision + 1,
      next.layout,
      next.settings,
    );
  }
}

class ResumePort implements MenuBrowserResumePort {
  var value = const MenuBrowserResume(
    1,
    true,
    'https://example.invalid/fixture',
  );
  final sources = <InteractionSource>[];
  bool fail = false;
  @override
  Future<MenuBrowserResume> read() async => value;
  @override
  Future<MenuBrowserResume> setEnabled(
    MenuBrowserResume saved,
    bool enabled,
  ) async {
    sources.add(currentStarBridgeActivationSource);
    if (fail) throw StateError('Synthetic resume refusal');
    return value = MenuBrowserResume(
      saved.revision + 1,
      enabled,
      enabled ? saved.url : null,
    );
  }

  @override
  Future<MenuBrowserResume> remember(
    MenuBrowserResume saved,
    String url,
  ) async => throw StateError('No URL write allowed in this fixture');
}

class MenuFixture {
  final port = MenuPort(), resume = ResumePort();
  late final additional = MenuAdditionalSettingsDraft(resumePort: resume);
  late final draft = MenuSettingsDraft(port)..attachAdditional(additional);
  Future<void> load() async {
    await draft.initialize();
    await additional.reload();
    draft.change({'showClock': false});
    additional.changeResume(false);
  }

  Future<void> clean(WidgetTester t) async {
    if (port.pending case final p? when !p.isCompleted) p.complete();
    await frames(t);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    draft.dispose();
  }
}

class MenuHarness extends StatefulWidget {
  const MenuHarness(this.fixture, this.suite, {super.key});
  final MenuFixture fixture;
  final InteractionSuite suite;
  @override
  State<MenuHarness> createState() => MenuHarnessState();
}

class MenuHarnessState extends State<MenuHarness> {
  bool reduce = false, light = false;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    MenuSettingsWorkspace(draft: widget.fixture.draft),
    widget.suite,
    reduce: reduce,
    light: light,
  );
}

class EditorHarness extends StatefulWidget {
  const EditorHarness(this.fixture, this.suite, {super.key});
  final FullFixture fixture;
  final InteractionSuite suite;
  @override
  State<EditorHarness> createState() => EditorHarnessState();
}

class EditorHarnessState extends State<EditorHarness> {
  bool reduce = false, light = false, visible = true;
  late var suite = widget.suite;
  final coalesces = <bool>[];
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) {
    final h = widget.fixture;
    return scopedApp(
      !visible
          ? const Text('Left editor')
          : ListenableBuilder(
              listenable: Listenable.merge([h.editor, h.module.projection]),
              builder: (context, _) {
                final p = h.module.projection.value;
                final item = p.layout.singleWhere((i) => i.key == 'Members');
                // Like the real page: no save bar, edits save on their own.
                return Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          OverlayWorkspaceEditorTools(
                            editor: h.editor,
                            allowSimulation: true,
                          ),
                          OverlayWorkspaceLayoutInspector(
                            item: item,
                            nudgePixels: h.editor.nudgePixels,
                            layoutLocked: h.editor.layoutLocked,
                            onChanged: (v, c) {
                              coalesces.add(c);
                              h.module.updateLayoutItem(v, coalesce: c);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      suite,
      reduce: reduce,
      light: light,
    );
  }
}

Future<void> view(WidgetTester t) async {
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<EditorHarnessState> mountEditor(
  WidgetTester t,
  FullFixture h,
  InteractionSuite suite,
) async {
  await view(t);
  await h.module.initialize();
  await t.pumpWidget(EditorHarness(h, suite));
  await frames(t);
  return t.state<EditorHarnessState>(find.byType(EditorHarness));
}

void main() {
  test(
    'captured command source follows confirming action and expires',
    () async {
      late InteractionSource Function() getter;
      await runStarBridgeActivation(InteractionSource.pointer, () async {
        getter = captureStarBridgeActivationSource();
        final finish = captureStarBridgeActivationCompletion();
        expect(getter(), InteractionSource.pointer);
        finish(InteractionSource.keyboard);
        expect(getter(), InteractionSource.keyboard);
      });
      expect(getter(), InteractionSource.programmatic);
    },
  );
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite actual information page has no save bar; undo and redo save',
      (t) async {
        final h = FullFixture();
        try {
          await view(t);
          await h.module.initialize();
          await t.pumpWidget(
            scopedApp(OverlayWorkspacePage(module: h.module), suite),
          );
          await frames(t);
          h.module.updateSetting('showMembers', true);
          await frames(t);
          expect(find.byType(OverlaySettingsSaveBar), findsNothing);
          expect(h.module.projection.value.dirty, isFalse);
          final status = find.byKey(const Key('overlay-preset-save-status'));
          expect(t.widget<Text>(status).data, '已保存');
          await key(t, 'keyboard', 'overlay-preset-undo');
          await frames(t);
          expect(h.module.projection.value.settings!['showMembers'], isFalse);
          expect(h.module.projection.value.dirty, isFalse);
          expect(h.module.canRedo, isTrue);
          h.module.redo();
          await frames(t);
          expect(h.module.projection.value.settings!['showMembers'], isTrue);
          expect(h.port.writes.map((w) => w.$1.settings!['showMembers']), [
            true,
            false,
            true,
          ]);
          expect(find.byType(OverlaySettingsSaveBar), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      },
    );
    testWidgets(
      '$suite native pixel edit survives suite change before commit',
      (t) async {
        final h = FullFixture();
        try {
          final state = await mountEditor(t, h, suite);
          final input = find.descendant(
            of: find.byKey(const Key('overlay-pixels-Members-x')),
            matching: find.byType(TextField),
          );
          await t.ensureVisible(input);
          final before = t.widget<TextField>(input).controller!;
          before.value = const TextEditingValue(
            text: '12.5',
            selection: TextSelection.collapsed(offset: 3),
            composing: TextRange(start: 0, end: 2),
          );
          state.change(
            () => state.suite = suite == InteractionSuite.scan
                ? InteractionSuite.glow
                : InteractionSuite.scan,
          );
          await frames(t);
          expect(t.widget<TextField>(input).controller, same(before));
          expect(before.value.text, '12.5');
          expect(before.value.composing, const TextRange(start: 0, end: 2));
          expect(h.module.projection.value.dirty, isFalse);
          expect(state.coalesces, isEmpty);
          expect(h.port.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      },
    );
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input anchor FormField uses original controlled value',
        (t) async {
          final h = FullFixture();
          try {
            final state = await mountEditor(t, h, suite);
            const anchor = 'overlay-layout-horizontal-anchor-Members';
            await key(t, input, '$anchor-command');
            await frames(t);
            await fire(
              t,
              input,
              find.byKey(const ValueKey<Object>((anchor, 'Right'))),
            );
            await frames(t);
            expect(
              h.module.projection.value.layout
                  .singleWhere((i) => i.key == 'Members')
                  .horizontalAnchor,
              'Right',
            );
            expect(state.coalesces.last, isFalse);
            expect(
              h.port.writes.last.$1.layout!
                  .singleWhere((i) => i.key == 'Members')
                  .horizontalAnchor,
              'Right',
            );
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
          }
        },
      );
    }
    for (final input in ['pointer', 'keyboard']) {
      testWidgets(
        '$suite $input locked geometry still permits opacity coalescing',
        (t) async {
          final h = FullFixture();
          try {
            final state = await mountEditor(t, h, suite);
            await key(t, 'pointer', 'overlay-layout-lock-Members');
            await frames(t);
            final row = find.byKey(
              const Key('overlay-layout-text-opacity-Members'),
            );
            await t.ensureVisible(row);
            final adapter = find.descendant(
              of: row,
              matching: find.byType(StarBridgeSlider),
            );
            final native = find.descendant(
              of: adapter,
              matching: find.byType(Slider),
            );
            final fx = find.descendant(
              of: adapter,
              matching: find.byType(SuiteSlider),
            );
            if (input == 'keyboard') {
              final node = native.evaluate().isNotEmpty
                  ? t.widget<Slider>(native).focusNode
                  : t.widget<SuiteSlider>(fx).focusNode;
              node!.requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
            } else {
              await t.drag(
                native.evaluate().isNotEmpty ? native : fx,
                const Offset(-80, 0),
              );
            }
            await frames(t);
            final item = h.module.projection.value.layout.singleWhere(
              (i) => i.key == 'Members',
            );
            expect(item.isLocked, isTrue);
            expect(item.textOpacity, lessThan(1));
            expect(state.coalesces.last, isTrue);
            final saved = h.port.writes.last.$1.layout!.singleWhere(
              (i) => i.key == 'Members',
            );
            expect(saved.isLocked, isTrue);
            expect(saved.textOpacity, item.textOpacity);
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
          }
        },
      );
    }
    for (final reject in [false, true]) {
      testWidgets(
        '$suite save reply after editor unmount reject=$reject remains owned',
        (t) async {
          final h = FullFixture();
          try {
            final state = await mountEditor(t, h, suite);
            h.port.pending = Completer<void>();
            h.port.reject = reject;
            h.module.updateSetting('showMembers', true);
            await frames(t);
            expect(h.port.writes, hasLength(1));
            state.change(() => state.visible = false);
            await frames(t);
            h.port.pending!.complete();
            await frames(t);
            expect(h.module.projection.value.dirty, reject);
            // A conflict re-reads once and retries before it reports.
            expect(h.port.writes, hasLength(reject ? 2 : 1));
            state.change(() => state.visible = true);
            await frames(t);
            expect(find.byType(SuiteBusyFrame), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
          }
        },
      );
    }
    for (final input in ['keyboard', 'reader']) {
      for (final confirm in [false, true]) {
        testWidgets(
          '$suite pointer-open $input confirm=$confirm instant dialog exit',
          (t) async {
            final h = MenuFixture();
            try {
              await view(t);
              await h.load();
              h.port.pending = Completer<void>();
              await t.pumpWidget(MenuHarness(h, suite));
              await frames(t);
              await key(t, 'pointer', 'menu-workspace-save');
              await frames(t);
              final target = confirm
                  ? 'menu-clear-memory-confirm'
                  : 'menu-clear-memory-cancel';
              final route =
                  ModalRoute.of(t.element(find.byKey(Key(target))))!
                      as StarBridgeDialogRoute<bool>;
              expect(route.instant, isFalse);
              await key(t, input, target);
              expect(route.animation?.status, isNot(AnimationStatus.reverse));
              await frames(t);
              expect(
                h.port.sources,
                confirm ? [InteractionSource.keyboard] : isEmpty,
              );
              if (confirm) {
                expect(h.draft.busy, isTrue);
                expect(
                  InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
                      .reduceMotion,
                  isTrue,
                );
              }
              expect(t.takeException(), isNull);
            } finally {
              await h.clean(t);
            }
          },
        );
      }
    }
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite $input assists are local and reversible', (t) async {
        final h = FullFixture();
        try {
          await mountEditor(t, h, suite);
          await key(t, input, 'overlay-editor-simulate');
          await key(t, input, 'overlay-layout-show-grid');
          await key(t, input, 'overlay-layout-grid-snap-toggle');
          await frames(t);
          expect(h.editor.simulateInformation, isFalse);
          expect(h.editor.showGrid, isFalse);
          expect(h.editor.snapToGrid, isTrue);
          await key(t, input, 'overlay-layout-grid-32');
          await key(t, input, 'overlay-layout-grid-64');
          await key(t, input, 'overlay-layout-nudge-5');
          await key(t, input, 'overlay-layout-smart-snap');
          await key(t, input, 'overlay-layout-lock-all');
          await frames(t);
          expect(h.editor.gridSize, 64);
          expect(h.editor.nudgePixels, 5);
          expect(h.editor.smartSnap, isFalse);
          expect(h.editor.layoutLocked, isTrue);
          expect(h.module.projection.value.dirty, isFalse);
          expect(h.port.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      });
      testWidgets('$suite $input inspector nudge lock reset keeps history', (
        t,
      ) async {
        final h = FullFixture();
        try {
          final state = await mountEditor(t, h, suite);
          final before = h.module.projection.value.layout.singleWhere(
            (i) => i.key == 'Members',
          );
          await key(t, input, 'overlay-layout-nudge-right-Members');
          await frames(t);
          final after = h.module.projection.value.layout.singleWhere(
            (i) => i.key == 'Members',
          );
          expect(after.x, greaterThan(before.x));
          expect(state.coalesces.last, isFalse);
          expect(
            h.port.writes.last.$1.layout!
                .singleWhere((i) => i.key == 'Members')
                .x,
            after.x,
          );
          await key(t, input, 'overlay-layout-lock-Members');
          await frames(t);
          expect(
            h.module.projection.value.layout
                .singleWhere((i) => i.key == 'Members')
                .isLocked,
            isTrue,
          );
          final semantics = t.ensureSemantics();
          try {
            expect(
              t
                  .getSemantics(
                    find.byKey(const Key('overlay-layout-nudge-right-Members')),
                  )
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
          } finally {
            semantics.dispose();
          }
          await key(t, input, 'overlay-layout-lock-Members');
          await frames(t);
          await key(t, input, 'overlay-layout-reset-Members');
          await frames(t);
          expect(h.module.canUndo, isTrue);
          expect(state.coalesces.every((c) => !c), isTrue);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      });
      for (final reject in [false, true]) {
        testWidgets(
          '$suite $input edit save reject=$reject keeps the edit, no optimistic outcome',
          (t) async {
            final h = FullFixture();
            try {
              await mountEditor(t, h, suite);
              h.port.pending = Completer<void>();
              h.port.reject = reject;
              await key(t, input, 'overlay-layout-nudge-right-Members');
              await frames(t);
              final nudged = h.module.projection.value.layout.singleWhere(
                (i) => i.key == 'Members',
              );
              expect(h.port.writes, hasLength(1));
              expect(h.module.projection.value.dirty, isTrue);
              // Editing stays open while the write runs.
              expect(h.module.projection.value.busy, isFalse);
              expect(find.byType(SuiteBusyFrame), findsNothing);
              h.port.pending!.complete();
              await frames(t);
              expect(h.module.projection.value.dirty, reject);
              expect(
                h.module.projection.value.failure,
                reject ? OverlaySettingsFailure.writeConflict : isNull,
              );
              expect(
                h.module.projection.value.layout
                    .singleWhere((i) => i.key == 'Members')
                    .toMap(),
                nudged.toMap(),
              );
              expect(t.takeException(), isNull);
            } finally {
              await h.clean(t);
            }
          },
        );
      }
      for (final outcome in ['cancel', 'success', 'partial']) {
        testWidgets('$suite $input real menu confirmation $outcome', (t) async {
          final h = MenuFixture();
          try {
            await view(t);
            await h.load();
            h.resume.fail = outcome == 'partial';
            await t.pumpWidget(MenuHarness(h, suite));
            await frames(t);
            await key(t, input, 'menu-workspace-save');
            await frames(t);
            expect(h.port.sources, isEmpty);
            expect(h.resume.sources, isEmpty);
            await key(
              t,
              input,
              outcome == 'cancel'
                  ? 'menu-clear-memory-cancel'
                  : 'menu-clear-memory-confirm',
            );
            await frames(t);
            final source = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            expect(h.port.sources, outcome == 'cancel' ? isEmpty : [source]);
            expect(h.resume.sources, outcome == 'cancel' ? isEmpty : [source]);
            expect(h.draft.dirty, outcome != 'success');
            if (outcome == 'partial') {
              expect(h.additional.resumeDirty, isTrue);
              expect(h.draft.settings['showClock'], isFalse);
              h.resume.fail = false;
              await key(t, input, 'menu-workspace-save');
              await frames(t);
              await key(t, input, 'menu-clear-memory-confirm');
              await frames(t);
              expect(h.port.sources, [
                source,
              ], reason: 'Do not replay the successful portion.');
              expect(h.resume.sources, [source, source]);
              expect(h.draft.dirty, isFalse);
            }
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
          }
        });
      }
    }
    testWidgets('$suite page undo retains labeled tooltip and truth', (
      t,
    ) async {
      final h = FullFixture();
      try {
        await view(t);
        await h.module.initialize();
        await t.pumpWidget(
          scopedApp(OverlayWorkspacePage(module: h.module), suite),
        );
        await frames(t);
        h.module.updateSetting('showMembers', true);
        await frames(t);
        expect(
          find.byWidgetPredicate(
            (w) => w is StarBridgeTooltip && w.message == '撤销',
          ),
          findsOneWidget,
        );
        await key(t, 'keyboard', 'overlay-preset-undo');
        await frames(t);
        expect(h.module.projection.value.dirty, isFalse);
        expect(h.module.projection.value.settings!['showMembers'], isFalse);
        expect(find.text('已保存'), findsOneWidget);
        await key(t, 'reader', 'overlay-preset-redo');
        await frames(t);
        expect(h.module.projection.value.settings!['showMembers'], isTrue);
        expect(h.module.projection.value.dirty, isFalse);
        expect(t.takeException(), isNull);
      } finally {
        await h.clean(t);
      }
    });
  }
}
