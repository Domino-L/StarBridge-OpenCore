import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/chrome/overlay_source_labels.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_picker.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_projection.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_shortcut_summary.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_runtime_card.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3b_test.dart' show ScenePort;
import 'interaction_batch3s_test.dart' as runtime_fixture show Port, runtime;
import 'interaction_batch3do_test.dart' show loadFonts, scopedApp, size;

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Fixture {
  _Fixture() {
    scenes = OverlaySceneController(scenePort, autoStart: false);
    workspace = OverlayWorkspaceModule(runtimePort);
  }
  final scenePort = ScenePort();
  final runtimePort = runtime_fixture.Port();
  late final OverlaySceneController scenes;
  late final OverlayWorkspaceModule workspace;
  final capture = GlobalKey();
  int parentEscapes = 0, runtimeActions = 0;
  Future<void> initialize() async {
    await scenes.refresh();
    await workspace.refresh();
  }

  Widget child(String family) => switch (family) {
    'scene' => OverlayScenePicker(controller: scenes, compact: true),
    'shortcut' => OverlayShortcutSummary(
      binding: workspace.projection.value.snapshot!.hotkey!.binding,
      enabled: workspace.projection.value.snapshot!.hotkey!.enabled,
      state: workspace.projection.value.runtime.hotkeyState,
    ),
    _ => ValueListenableBuilder<OverlayWorkspaceProjection>(
      valueListenable: workspace.projection,
      builder: (context, projection, _) => OverlayWorkspaceRuntimeCard(
        projection: projection,
        compact: true,
        onAction: () {
          runtimeActions++;
          unawaited(workspace.openRuntime('zh'));
        },
      ),
    ),
  };
  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    scenes.dispose();
    workspace.dispose();
    final pending = runtimePort.heldRuntime;
    if (pending != null && !pending.isCompleted) {
      pending.complete(runtime_fixture.runtime('open'));
    }
    if (!scenePort.pending.isCompleted) {
      scenePort.pending.complete(scenePort.state);
    }
    await _frames(t);
    await t.runAsync(scenePort.events.close);
  }
}

Future<void> _mount(
  WidgetTester t,
  _Fixture f,
  String family,
  InteractionSuite suite, {
  bool reduce = false,
}) async {
  await t.pumpWidget(
    RepaintBoundary(
      key: f.capture,
      child: scopedApp(
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                f.parentEscapes++,
          },
          child: Focus(
            autofocus: true,
            child: SizedBox(width: 650, child: f.child(family)),
          ),
        ),
        suite,
        reduce: reduce,
      ),
    ),
  );
  await _frames(t);
}

String _message(_Fixture f, String family) {
  final strings = AppStrings.resolve(const Locale('zh', 'CN'));
  if (family == 'scene') {
    final view = projectOverlayScene(f.scenes.projection.value);
    return strings.text(view.fallbackReasonKey ?? overlaySourceHint(view));
  }
  final runtime = f.workspace.projection.value.runtime;
  if (family == 'shortcut') {
    return strings.text('overlay.runtime.hotkey.${runtime.hotkeyState}');
  }
  final description = switch (runtime.windowState) {
    'open' => 'overlay.runtime.openDescription',
    'suppressed' => 'overlay.runtime.suppressedDescription',
    'opening' => 'overlay.runtime.preparingDescription',
    'failed' || 'unavailable' => switch (runtime.failureCode) {
      'overlay.runtime_start_timeout' => 'overlay.runtime.timeoutDescription',
      'overlay.runtime_permission_denied' =>
        'overlay.runtime.permissionDescription',
      _ => 'overlay.runtime.failedDescription',
    },
    _ => 'overlay.runtime.closedDescription',
  };
  return '${strings.text(description)}\n${strings.text('overlay.runtime.hotkey.${runtime.hotkeyState}')}\n${strings.text('overlay.runtime.follow.${runtime.followGameState}')}'
      '${runtime.usedFallbackSkin ? '\n${strings.text('overlay.runtime.skinFallback')}' : ''}';
}

Finder _hint(String message) => find.byWidgetPredicate(
  (w) => w is StarBridgeTooltip && w.message == message,
);

SuiteTooltipState _hintState(WidgetTester t, Finder hint) =>
    t.state<SuiteTooltipState>(
      find.descendant(of: hint, matching: find.byType(SuiteTooltip)),
    );

Future<void> _show(WidgetTester t, Finder target, String gesture) async {
  await t.ensureVisible(target);
  if (gesture == 'touch') {
    await t.longPress(target);
    await _frames(t, 2);
  } else {
    final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(target));
    await _frames(t, 7);
  }
}

Future<Uint8List> _pixels(WidgetTester t, _Fixture f) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(f.capture));
  return (await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final family in ['scene', 'shortcut', 'runtime']) {
      for (final gesture in ['hover', 'touch']) {
        testWidgets(
          '$suite $family $gesture hint is passive and parent Escape still runs',
          (t) async {
            size(t, const Size(1000, 850));
            final f = _Fixture();
            await f.initialize();
            final saved = f.workspace.projection.value.snapshot;
            final scene = f.scenes.projection.value;
            final calls = f.runtimePort.runtimeCalls.length;
            try {
              await _mount(t, f, family, suite);
              final message = _message(f, family);
              final hint = _hint(message);
              expect(hint, findsOneWidget);
              expect(t.widget<StarBridgeTooltip>(hint).consumeEscape, isFalse);
              await _show(t, hint, gesture);
              final state = _hintState(t, hint);
              expect(state.isShowing, isTrue);
              expect(find.text(message), findsWidgets);
              expect(f.runtimeActions, 0);
              expect(f.runtimePort.runtimeCalls.length, calls);
              expect(f.runtimePort.writes, isEmpty);
              expect(f.scenePort.writes, 0);
              expect(f.workspace.projection.value.snapshot, same(saved));
              expect(f.scenes.projection.value, same(scene));
              expect(
                nativeViewportMenus.value,
                0,
                reason: 'A hint is not the source menu.',
              );
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await _frames(t);
              expect(f.parentEscapes, 1);
              expect(state.isShowing, isFalse);
              expect(f.runtimeActions, 0);
              expect(f.scenePort.writes, 0);
              expect(t.takeException(), isNull);
            } finally {
              await f.close(t);
            }
          },
          timeout: const Timeout(Duration(seconds: 45)),
        );
      }

      testWidgets(
        '$suite $family reduced-motion hint is static without changing status',
        (t) async {
          size(t, const Size(1000, 850));
          final f = _Fixture();
          await f.initialize();
          try {
            await _mount(t, f, family, suite, reduce: true);
            final message = _message(f, family);
            final hint = _hint(message);
            await _show(t, hint, 'hover');
            expect(_hintState(t, hint).isShowing, isTrue);
            final opacity = find.ancestor(
              of: find.text(message).last,
              matching: find.byType(Opacity),
            );
            expect(opacity, findsOneWidget);
            expect(t.widget<Opacity>(opacity).opacity, 1);
            final before = await _pixels(t, f);
            await _frames(t, 3);
            expect(listEquals(before, await _pixels(t, f)), isTrue);
            expect(f.runtimeActions, 0);
            expect(f.scenePort.writes, 0);
            expect(f.runtimePort.writes, isEmpty);
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await _frames(t);
            expect(f.parentEscapes, 1);
            expect(t.takeException(), isNull);
          } finally {
            await f.close(t);
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets(
      '$suite shortcut saved binding and all original status mappings stay unchanged',
      (t) async {
        size(t, const Size(1000, 850));
        final strings = AppStrings.resolve(const Locale('zh', 'CN'));
        for (final state in [
          'registered',
          'gameCompatibleOnly',
          'desktopOnly',
          'conflictWithInformation',
          'conflict',
          'modifierRequired',
          'reserved',
          'invalid',
          'failed',
          'unrecognized',
        ]) {
          for (final enabled in [true, false]) {
            final expectedState = !enabled
                ? 'disabled'
                : switch (state) {
                    'registered' ||
                    'gameCompatibleOnly' ||
                    'desktopOnly' => state,
                    'conflictWithInformation' || 'conflict' => 'conflict',
                    'modifierRequired' || 'reserved' || 'invalid' => 'invalid',
                    'failed' => 'failed',
                    _ => 'unavailable',
                  };
            await t.pumpWidget(
              scopedApp(
                OverlayShortcutSummary(
                  binding: 'Alt+O',
                  enabled: enabled,
                  state: state,
                ),
                suite,
              ),
            );
            await _frames(t);
            final message = strings.text(
              'overlay.runtime.hotkey.$expectedState',
            );
            expect(_hint(message), findsOneWidget);
            expect(
              t.widget<StarBridgeTooltip>(_hint(message)).consumeEscape,
              isFalse,
            );
            expect(find.text('Alt+O'), findsOneWidget);
            expect(
              find.text(message),
              const {
                    'registered',
                    'gameCompatibleOnly',
                    'desktopOnly',
                  }.contains(expectedState)
                  ? findsNothing
                  : findsOneWidget,
            );
            expect(find.byType(StarBridgeActionButton), findsNothing);
          }
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite disabled scene hint keeps original gate and does not select',
      (t) async {
        size(t, const Size(1000, 850));
        final f = _Fixture();
        await f.initialize();
        try {
          f.scenePort.state = const OverlaySceneState(status: 'signedOut');
          await f.scenes.refresh();
          await _mount(t, f, 'scene', suite);
          final view = projectOverlayScene(f.scenes.projection.value);
          expect(view.canChange, isFalse);
          final trigger = find.byKey(const Key('overlay-source-picker'));
          final button = find.ancestor(
            of: trigger,
            matching: find.byType(StarBridgeActionButton),
          );
          expect(t.widget<StarBridgeActionButton>(button).onActivate, isNull);
          final hint = _hint(_message(f, 'scene'));
          await _show(t, hint, 'hover');
          expect(_hintState(t, hint).isShowing, isTrue);
          await t.tapAt(t.getCenter(trigger));
          await _frames(t);
          expect(f.scenePort.writes, 0);
          expect(f.scenePort.arguments, isEmpty);
          expect(nativeViewportMenus.value, 0);
          expect(f.runtimeActions, 0);
          expect(t.takeException(), isNull);
        } finally {
          await f.close(t);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite compact runtime hint cannot repeat actual held command',
      (t) async {
        size(t, const Size(1000, 850));
        final f = _Fixture();
        await f.initialize();
        final saved = f.workspace.projection.value.snapshot;
        try {
          await _mount(t, f, 'runtime', suite);
          final initialCalls = f.runtimePort.runtimeCalls.length;
          f.runtimePort.heldRuntime = Completer<OverlayRuntimeSnapshot>();
          await t.tap(find.byKey(const Key('overlay-runtime-action')));
          await _frames(t);
          expect(f.runtimeActions, 1);
          expect(f.runtimePort.runtimeCalls.length, initialCalls + 1);
          expect(f.runtimePort.runtimeCalls.last, OverlayRuntimeAction.open);
          expect(f.workspace.projection.value.runtimeBusy, isTrue);
          expect(
            t
                .widget<StarBridgeActionButton>(
                  find.byKey(const Key('overlay-runtime-action')),
                )
                .onActivate,
            isNull,
          );
          final hint = _hint(_message(f, 'runtime'));
          await _show(t, hint, 'touch');
          expect(_hintState(t, hint).isShowing, isTrue);
          await t.tapAt(
            t.getCenter(find.byKey(const Key('overlay-runtime-action'))),
          );
          await _frames(t);
          expect(f.runtimeActions, 1);
          expect(f.runtimePort.runtimeCalls.length, initialCalls + 1);
          expect(f.workspace.projection.value.snapshot, same(saved));
          expect(f.runtimePort.writes, isEmpty);
          f.runtimePort.heldRuntime!.complete(runtime_fixture.runtime('open'));
          await _frames(t);
          expect(f.workspace.projection.value.runtime.windowState, 'open');
          expect(f.workspace.projection.value.runtimeBusy, isFalse);
          expect(f.runtimeActions, 1);
          expect(t.takeException(), isNull);
        } finally {
          await f.close(t);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
