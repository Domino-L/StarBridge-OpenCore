import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_fullscreen.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_editor_state.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/platform/window/overlay_editor_window_port.dart';

import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import '../../features/overlay_settings/overlay_preset_transfer_test.dart'
    show layout;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bt_test.dart' show hit;
import 'interaction_batch3bw_test.dart' show frames;

class WindowPort implements OverlayEditorWindowPort {
  final calls = <(String, InteractionSource)>[];
  Completer<void>? pending;
  bool failEnter = false, failExit = false;
  @override
  Future<void> enter() async {
    calls.add(('enter', currentStarBridgeActivationSource));
    await pending?.future;
    if (failEnter) throw StateError('Synthetic enter failure');
  }

  @override
  Future<void> exit() async {
    calls.add(('exit', currentStarBridgeActivationSource));
    if (failExit) throw StateError('Synthetic exit failure');
  }
}

class WorkspacePort implements OverlayWorkspacePort {
  int revision = 1;
  var values = settings({'showMembers': false});
  var geometry = [
    for (var i = 0; i < layout.length; i++)
      OverlayWorkspaceLayoutItem(
        key: layout[i].key,
        x: .04 + i * .23,
        y: .04 + i * .2,
        width: .2,
        height: .2,
        horizontalAnchor: 'Left',
        verticalAnchor: 'Top',
        isLocked: false,
        textOpacity: 1,
        backgroundOpacity: .5,
      ),
  ];
  final writes = <(OverlayWorkspaceMutation, InteractionSource)>[];
  final runtimeCalls = <(OverlayRuntimeAction, InteractionSource)>[];
  Completer<void>? pending;
  bool reject = false;
  String runtimeState = 'closed';
  OverlayWorkspaceSnapshot get snapshot => OverlayWorkspaceSnapshot.available(
    revision: revision,
    storageState: 'ready',
    activePresetId: 'one',
    renderMode: 'NativeComposition',
    appearances: const [],
    hotkey: const OverlayWorkspaceHotkey(
      binding: 'Alt+O',
      enabled: true,
      runtimeState: 'registered',
    ),
    settings: values,
    layout: geometry,
    presets: [
      OverlayWorkspacePreset(
        id: 'one',
        name: '测试预设',
        isActive: true,
        storageState: 'ready',
        settings: values,
        layout: geometry,
      ),
    ],
  );
  @override
  Future<OverlayWorkspaceSnapshot> read() async => snapshot;
  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    expectSync(expectedRevision, revision);
    writes.add((mutation, currentStarBridgeActivationSource));
    await pending?.future;
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

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async {
    runtimeCalls.add((action, currentStarBridgeActivationSource));
    if (action != OverlayRuntimeAction.getState) {
      runtimeState = action == OverlayRuntimeAction.close ? 'closed' : 'open';
    }
    return OverlayRuntimeSnapshot(
      windowState: runtimeState,
      isVisible: runtimeState == 'open',
      appliedRevision: revision,
      hotkeyState: 'registered',
      followGameState: 'manual',
      requestedSkin: 'Default',
      effectiveSkin: 'Default',
      usedFallbackSkin: false,
    );
  }

  @override
  Future<void> close() async {}
}

class FullFixture {
  final window = WindowPort(), port = WorkspacePort();
  final editor = OverlayWorkspaceEditorState();
  late final module = OverlayWorkspaceModule(port, editorWindow: window);
  Future<void> clean(WidgetTester t) async {
    if (window.pending case final p? when !p.isCompleted) p.complete();
    if (port.pending case final p? when !p.isCompleted) p.complete();
    await frames(t);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    module.dispose();
    editor.dispose();
  }
}

class FullHarness extends StatefulWidget {
  const FullHarness(this.fixture, this.suite, {super.key});
  final FullFixture fixture;
  final InteractionSuite suite;
  @override
  State<FullHarness> createState() => FullHarnessState();
}

class FullHarnessState extends State<FullHarness> {
  bool reduce = false, light = false, opener = true;
  bool localScope = false;
  void change(VoidCallback update) => setState(update);
  @override
  Widget build(BuildContext context) => scopedApp(
    StarBridgeInteractionConfiguration(
      suite: widget.suite,
      reduceMotion: reduce,
      child: Center(
        child: opener
            ? OverlayWorkspaceFullscreenButton(
                module: widget.fixture.module,
                editor: widget.fixture.editor,
              )
            : const Text('Responsive replacement'),
      ),
    ),
    localScope ? InteractionSuite.standard : widget.suite,
    reduce: localScope ? false : reduce,
    light: light,
  );
}

Future<FullHarnessState> mountFull(
  WidgetTester t,
  FullFixture h,
  InteractionSuite suite, {
  bool open = true,
  String input = 'pointer',
}) async {
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await h.module.initialize();
  await t.pumpWidget(FullHarness(h, suite));
  await frames(t);
  final state = t.state<FullHarnessState>(find.byType(FullHarness));
  if (open) {
    await hit(t, input, 'overlay-enter-fullscreen');
    await frames(t);
    expect(find.byKey(const Key('overlay-fullscreen-editor')), findsOneWidget);
  }
  return state;
}

InteractionSource inputSource(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;

Future<void> hitIcon(WidgetTester t, String input, String key) async {
  if (input != 'keyboard') return hit(t, input, key);
  final glyph = find
      .descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(StarBridgeIcon),
      )
      .first;
  Focus.of(t.element(glyph)).requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await frames(t);
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final reject in [false, true]) {
      testWidgets(
        '$suite leave before save reply reject=$reject retains owner',
        (t) async {
          final h = FullFixture();
          try {
            await mountFull(t, h, suite);
            h.port.pending = Completer<void>();
            h.port.reject = reject;
            h.module.updateSetting('showMembers', true);
            await frames(t);
            expect(h.port.writes, hasLength(1));
            await hit(t, 'keyboard', 'overlay-exit-fullscreen');
            await frames(t);
            expect(
              find.byKey(const Key('overlay-fullscreen-editor')),
              findsNothing,
            );
            expect(h.module.projection.value.dirty, isTrue);
            h.port.pending!.complete();
            await frames(t);
            // A conflict re-reads once and retries before it reports.
            expect(h.port.writes, hasLength(reject ? 2 : 1));
            expect(h.module.projection.value.busy, isFalse);
            expect(h.module.projection.value.dirty, reject);
            await hit(t, 'keyboard', 'overlay-enter-fullscreen');
            await frames(t);
            expect(
              h.module.projection.value.failure,
              reject ? OverlaySettingsFailure.writeConflict : isNull,
            );
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
          }
        },
      );
    }
    testWidgets('$suite CtrlS never duplicates a running or finished save', (
      t,
    ) async {
      final h = FullFixture();
      Future<void> ctrlS() async {
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.keyS);
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await frames(t);
      }

      try {
        await mountFull(t, h, suite);
        h.port.pending = Completer<void>();
        h.module.updateSetting('showMembers', true);
        await frames(t);
        expect(h.port.writes, hasLength(1));
        final status = find.byKey(const Key('overlay-fullscreen-save-status'));
        expect(t.widget<Text>(status).data, '正在保存更改…');
        Focus.of(t.element(status)).requestFocus();
        await t.pump();
        await ctrlS();
        expect(h.port.writes, hasLength(1), reason: 'waits for the running save');
        h.port.pending!.complete();
        await frames(t);
        expect(h.module.projection.value.dirty, isFalse);
        expect(t.widget<Text>(status).data, '所有更改已保存');
        await ctrlS();
        expect(h.port.writes, hasLength(1), reason: 'nothing left to save');
        expect(t.takeException(), isNull);
      } finally {
        await h.clean(t);
      }
    });
    testWidgets('$suite pending native enter has one request and F11 leaves', (
      t,
    ) async {
      final h = FullFixture()..window.pending = Completer<void>();
      try {
        await mountFull(t, h, suite, open: false);
        await hit(t, 'pointer', 'overlay-enter-fullscreen');
        await frames(t);
        final semantics = t.ensureSemantics();
        try {
          final data = t
              .getSemantics(find.byKey(const Key('overlay-enter-fullscreen')))
              .getSemanticsData();
          expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
        } finally {
          semantics.dispose();
        }
        expect(h.window.calls, hasLength(1));
        h.window.pending!.complete();
        await frames(t);
        Focus.of(
          t.element(find.byKey(const Key('overlay-fullscreen-save-status'))),
        ).requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.f11);
        await frames(t);
        expect(
          find.byKey(const Key('overlay-fullscreen-editor')),
          findsNothing,
        );
        expect(t.takeException(), isNull);
      } finally {
        await h.clean(t);
      }
    });
    testWidgets('$suite local suite below navigator remains effective', (
      t,
    ) async {
      final h = FullFixture();
      try {
        final state = await mountFull(t, h, suite, open: false);
        state.change(() => state.localScope = true);
        await frames(t);
        await hit(t, 'pointer', 'overlay-enter-fullscreen');
        await frames(t);
        final saveLabel = find.byKey(
          const Key('overlay-fullscreen-save-status'),
        );
        expect(InteractionScope.of(t.element(saveLabel)).suite, suite);
        state.change(() => state.reduce = true);
        await frames(t);
        expect(InteractionScope.of(t.element(saveLabel)).reduceMotion, isTrue);
        expect(t.takeException(), isNull);
      } finally {
        await h.clean(t);
      }
    });
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite $input native window and route retain contract', (
        t,
      ) async {
        final h = FullFixture();
        try {
          await mountFull(t, h, suite, input: input);
          expect(h.window.calls.first, ('enter', inputSource(input)));
          final route = ModalRoute.of(
            t.element(find.byKey(const Key('overlay-fullscreen-editor'))),
          )!;
          expect(route, isA<PageRouteBuilder<void>>());
          expect(route.transitionDuration, Duration.zero);
          expect(route.reverseTransitionDuration, Duration.zero);
          h.module.updateSetting('showMembers', true);
          await frames(t);
          await hit(t, input, 'overlay-exit-fullscreen');
          await frames(t);
          expect(
            find.byKey(const Key('overlay-fullscreen-editor')),
            findsNothing,
          );
          expect(h.window.calls[1], ('exit', inputSource(input)));
          // Preserve original idempotent exit in launcher's finally.
          expect(h.window.calls.map((c) => c.$1), ['enter', 'exit', 'exit']);
          expect(h.module.projection.value.dirty, isFalse);
          expect(h.module.projection.value.settings!['showMembers'], isTrue);
          expect(h.editor.fullscreenOpening, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      });
      testWidgets('$suite $input tools undo redo save and retain owner', (
        t,
      ) async {
        final h = FullFixture();
        try {
          await mountFull(t, h, suite);
          h.module.updateSetting('showMembers', true);
          await frames(t);
          await hitIcon(t, input, 'overlay-fullscreen-undo');
          await frames(t);
          expect(h.module.projection.value.settings!['showMembers'], isFalse);
          await hitIcon(t, input, 'overlay-fullscreen-redo');
          await frames(t);
          expect(h.module.projection.value.settings!['showMembers'], isTrue);
          expect(h.module.projection.value.dirty, isFalse);
          expect(h.port.writes.map((w) => w.$1.settings!['showMembers']), [
            true,
            false,
            true,
          ]);
          await hit(t, input, 'overlay-toggle-tools');
          await frames(t);
          expect(h.editor.toolsVisible, isFalse);
          await hit(t, input, 'overlay-toggle-tools');
          await frames(t);
          expect(h.editor.toolsVisible, isTrue);
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      });
      testWidgets('$suite $input enter and exit failures remain retryable', (
        t,
      ) async {
        final h = FullFixture()..window.failEnter = true;
        try {
          await mountFull(t, h, suite, open: false);
          await hit(t, input, 'overlay-enter-fullscreen');
          await frames(t);
          expect(
            find.byKey(const Key('overlay-fullscreen-editor')),
            findsNothing,
          );
          expect(h.editor.fullscreenOpening, isFalse);
          expect(h.window.calls, [('enter', inputSource(input))]);
          h.window.failEnter = false;
          await hit(t, input, 'overlay-enter-fullscreen');
          await frames(t);
          h.window.failExit = true;
          await hit(t, input, 'overlay-exit-fullscreen');
          await frames(t);
          expect(
            find.byKey(const Key('overlay-fullscreen-editor')),
            findsOneWidget,
          );
          h.window.failExit = false;
          await hit(t, input, 'overlay-exit-fullscreen');
          await frames(t);
          expect(
            find.byKey(const Key('overlay-fullscreen-editor')),
            findsNothing,
          );
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      });
    }
    for (final reject in [false, true]) {
      testWidgets(
        '$suite pending save reject=$reject keeps editing open, then shows the truth',
        (t) async {
          final h = FullFixture();
          try {
            await mountFull(t, h, suite);
            h.port.pending = Completer<void>();
            h.port.reject = reject;
            h.module.updateSetting('showMembers', true);
            await frames(t);
            expect(h.port.writes, hasLength(1));
            expect(h.module.projection.value.dirty, isTrue);
            expect(h.module.projection.value.busy, isFalse);
            expect(find.byType(SuiteBusyFrame), findsNothing);
            final status = find.byKey(
              const Key('overlay-fullscreen-save-status'),
            );
            expect(t.widget<Text>(status).data, '正在保存更改…');
            h.port.pending!.complete();
            await frames(t);
            expect(h.module.projection.value.dirty, reject);
            expect(
              h.module.projection.value.failure,
              reject ? OverlaySettingsFailure.writeConflict : isNull,
            );
            expect(t.widget<Text>(status).data, reject ? '未保存' : '所有更改已保存');
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
          }
        },
      );
    }
    testWidgets('$suite async enter survives responsive opener replacement', (
      t,
    ) async {
      final h = FullFixture()..window.pending = Completer<void>();
      try {
        final state = await mountFull(t, h, suite, open: false);
        await hit(t, 'keyboard', 'overlay-enter-fullscreen');
        await frames(t);
        expect(h.editor.fullscreenOpening, isTrue);
        expect(h.window.calls, hasLength(1));
        state.change(() => state.opener = false);
        await frames(t);
        h.window.pending!.complete();
        await frames(t);
        expect(
          find.byKey(const Key('overlay-fullscreen-editor')),
          findsOneWidget,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await frames(t);
        expect(h.editor.fullscreenOpening, isFalse);
        expect(t.takeException(), isNull);
      } finally {
        await h.clean(t);
      }
    });
    testWidgets('$suite live reduce and palette follow opened route', (
      t,
    ) async {
      final h = FullFixture();
      try {
        final state = await mountFull(t, h, suite);
        state.change(() {
          state.reduce = true;
          state.light = true;
        });
        await frames(t);
        final node = t.element(
          find.byKey(const Key('overlay-fullscreen-editor')),
        );
        expect(InteractionScope.of(node).reduceMotion, isTrue);
        expect(InteractionScope.of(node).palette.brightness, Brightness.light);
        h.port.pending = Completer<void>();
        h.module.updateSetting('showMembers', true);
        await frames(t);
        final status = find.byKey(const Key('overlay-fullscreen-save-status'));
        expect(t.widget<Text>(status).data, '正在保存更改…');
        expect(InteractionScope.of(t.element(status)).reduceMotion, isTrue);
        expect(t.takeException(), isNull);
      } finally {
        await h.clean(t);
      }
    });
    for (final runtime in [
      'closed',
      'open',
      'opening',
      'suppressed',
      'failed',
      'unavailable',
    ]) {
      testWidgets('$suite runtime=$runtime routes original action', (t) async {
        final h = FullFixture()..port.runtimeState = runtime;
        try {
          await mountFull(t, h, suite);
          await hit(t, 'keyboard', 'overlay-fullscreen-runtime-action');
          await frames(t);
          final expected = switch (runtime) {
            'open' || 'opening' || 'suppressed' => OverlayRuntimeAction.close,
            'failed' => OverlayRuntimeAction.retry,
            'unavailable' => OverlayRuntimeAction.getState,
            _ => OverlayRuntimeAction.open,
          };
          expect(h.port.runtimeCalls.last, (
            expected,
            InteractionSource.keyboard,
          ));
          expect(t.takeException(), isNull);
        } finally {
          await h.clean(t);
        }
      });
    }
  }
}
