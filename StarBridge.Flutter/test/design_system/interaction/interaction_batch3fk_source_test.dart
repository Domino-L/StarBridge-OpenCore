import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_port.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/widgets/overlay_scene_selector.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

const sourceProjection = OverlaySceneProjection(
  options: [
    OverlaySceneOption(id: 'auto', labelKey: '', label: 'Auto source'),
    OverlaySceneOption(id: 'room', labelKey: '', label: 'Room source'),
    OverlaySceneOption(
      id: 'locked',
      labelKey: '',
      label: 'Unavailable source',
      enabled: false,
    ),
  ],
  preferredSceneId: 'auto',
  actualSceneId: 'room',
  canChange: true,
);

class SourcePort implements ShellChromePort {
  final owner = InMemoryShellChrome(
    initial: InMemoryShellChrome.connectedProjection.copyWith(
      overlay: sourceProjection,
    ),
  );
  final calls = <(String, InteractionSource)>[];
  final completions = <InteractionSource>[];
  Completer<SceneSelectionResult>? held;
  @override
  ValueListenable<ShellChromeProjection> get projection => owner.projection;
  @override
  Future<SceneSelectionResult> selectOverlayScene(String id) async {
    calls.add((id, currentStarBridgeActivationSource));
    final result =
        await (held?.future ?? Future.value(SceneSelectionResult.saved));
    completions.add(currentStarBridgeActivationSource);
    if (result == SceneSelectionResult.saved) {
      await owner.selectOverlayScene(id);
    }
    return result;
  }
}

Future<void> sourceFrames(WidgetTester t, [int count = 6]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> sourceInput(WidgetTester t, Finder target, String input) async {
  await t.ensureVisible(target);
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'reader') {
    final node = t.getSemantics(target);
    final candidates = <ui.SemanticsAction>[ui.SemanticsAction.tap];
    expect(node.getSemanticsData().hasAction(candidates.single), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      candidates.single,
    );
  } else {
    final control = t.widget(target);
    final focus = switch (control) {
      SuitePressable button => button.focusNode!,
      MenuItemButton button => button.focusNode!,
      ButtonStyleButton button => button.focusNode!,
      _ => throw StateError('Unsupported real input target $control'),
    };
    for (var i = 0; !focus.hasPrimaryFocus && i < 30; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.pump();
    }
    expect(focus.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await t.pump();
  await t.pump();
}

Widget sourceView(
  SourcePort port,
  InteractionSuite suite, {
  bool reduce = false,
}) => scopedApp(
  ValueListenableBuilder<ShellChromeProjection>(
    valueListenable: port.projection,
    builder: (_, view, _) => OverlaySceneSelector(
      projection: view.overlay,
      port: port,
      mode: ShellLayoutMode.wide,
    ),
  ),
  suite,
  reduce: reduce,
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final opening in ['pointer', 'keyboard']) {
      testWidgets(
        '3fk $suite mixed $opening opening lets final choice own source',
        (t) async {
          size(t, const Size(1000, 850));
          final port = SourcePort();
          await t.pumpWidget(sourceView(port, suite));
          await sourceFrames(t);
          await sourceInput(
            t,
            find.byKey(const Key('overlay-scene-selector')),
            opening,
          );
          await sourceFrames(t);
          final choice = opening == 'pointer' ? 'keyboard' : 'pointer';
          await sourceInput(
            t,
            find.byKey(const ValueKey<Object>('overlay-source-room')),
            choice,
          );
          await sourceFrames(t);
          final source = choice == 'pointer'
              ? InteractionSource.pointer
              : InteractionSource.keyboard;
          expect(port.calls, [('room', source)]);
          expect(port.completions, [source]);
          expect(port.projection.value.overlay.preferredSceneId, 'room');
          expect(nativeViewportMenus.value, 0);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      '3fk $suite leaving during admitted selection cannot revive menu',
      (t) async {
        size(t, const Size(1000, 850));
        final port = SourcePort();
        final gate = port.held = Completer<SceneSelectionResult>();
        await t.pumpWidget(sourceView(port, suite));
        await sourceFrames(t);
        await sourceInput(
          t,
          find.byKey(const Key('overlay-scene-selector')),
          'keyboard',
        );
        await sourceFrames(t);
        await sourceInput(
          t,
          find.byKey(const ValueKey<Object>('overlay-source-room')),
          'keyboard',
        );
        expect(port.calls, [('room', InteractionSource.keyboard)]);
        await t.pumpWidget(const SizedBox());
        expect(nativeViewportMenus.value, 0);
        gate.complete(SceneSelectionResult.saved);
        await sourceFrames(t);
        // The original owner may finish its save; a departed view cannot reopen.
        expect(port.projection.value.overlay.preferredSceneId, 'room');
        expect(port.completions, [InteractionSource.keyboard]);
        expect(find.byType(SuiteSurfaceTransition), findsNothing);
        expect(nativeViewportMenus.value, 0);
        expect(t.takeException(), isNull);
      },
    );
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final outcome in [
        SceneSelectionResult.saved,
        SceneSelectionResult.rejected,
      ]) {
        testWidgets(
          '3fk $suite $input source menu held $outcome preserves actual origin',
          (t) async {
            size(t, const Size(1000, 850));
            final semantics = t.ensureSemantics();
            final port = SourcePort();
            final gate = port.held = Completer<SceneSelectionResult>();
            try {
              await t.pumpWidget(sourceView(port, suite));
              await sourceFrames(t);
              final trigger = find.byKey(const Key('overlay-scene-selector'));
              await sourceInput(t, trigger, input);
              expect(nativeViewportMenus.value, 1);
              final surface = find.byType(SuiteSurfaceTransition);
              expect(surface, findsOneWidget);
              expect(
                t.widget<SuiteSurfaceTransition>(surface).animation.value,
                input == 'pointer' ? lessThan(1) : 1,
              );
              await sourceFrames(t);
              final locked = find.byKey(
                const ValueKey<Object>('overlay-source-locked'),
              );
              final disabled = exposedNodes(t)
                  .where(
                    (node) =>
                        node.getSemanticsData().label == 'Unavailable source',
                  )
                  .toList();
              expect(disabled, hasLength(1));
              expect(
                disabled.single.getSemanticsData().hasAction(
                  ui.SemanticsAction.tap,
                ),
                isFalse,
              );
              await t.tapAt(t.getCenter(locked));
              await t.pump();
              expect(port.calls, isEmpty);
              await sourceInput(
                t,
                find.byKey(const ValueKey<Object>('overlay-source-room')),
                input,
              );
              final expected = input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard;
              expect(port.calls, [('room', expected)]);
              expect(port.projection.value.overlay.preferredSceneId, 'auto');
              await sourceFrames(t);
              expect(nativeViewportMenus.value, 0);
              gate.complete(outcome);
              await sourceFrames(t);
              expect(port.completions, [expected]);
              expect(
                port.projection.value.overlay.preferredSceneId,
                outcome == SceneSelectionResult.saved ? 'room' : 'auto',
              );
              expect(port.projection.value.overlay.actualSceneId, 'room');
              expect(port.calls, hasLength(1));
              expect(t.takeException(), isNull);
            } finally {
              if (!gate.isCompleted) {
                gate.complete(SceneSelectionResult.rejected);
              }
              await t.pumpWidget(const SizedBox());
              await t.pump();
              semantics.dispose();
            }
          },
        );
      }
    }
    testWidgets(
      '3fk $suite scene disabled transition balances menu without commands',
      (t) async {
        size(t, const Size(1000, 850));
        final port = SourcePort();
        await t.pumpWidget(sourceView(port, suite));
        await sourceFrames(t);
        await sourceInput(
          t,
          find.byKey(const Key('overlay-scene-selector')),
          'keyboard',
        );
        expect(nativeViewportMenus.value, 1);
        port.owner.replace(
          port.projection.value.copyWith(
            overlay: sourceProjection.copyWith(
              canChange: false,
              fallbackReasonKey: 'overlay.hostUnavailable',
            ),
          ),
        );
        await sourceFrames(t);
        expect(nativeViewportMenus.value, 0);
        final control = t.widget(
          find.byKey(const Key('overlay-scene-selector')),
        );
        expect(
          control is SuitePressable
              ? control.onActivate
              : (control as ButtonStyleButton).onPressed,
          isNull,
        );
        expect(port.calls, isEmpty);
        await t.pumpWidget(const SizedBox());
        expect(nativeViewportMenus.value, 0);
      },
    );
  }
}
