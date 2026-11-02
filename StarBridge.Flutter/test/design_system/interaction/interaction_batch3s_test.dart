import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_hotkey_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_runtime_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3m_test.dart' show activate;
import 'interaction_batch3b_test.dart' show semanticTap, exposedNodes;
import 'interaction_batch3o_test.dart' as base;

Future<void> iconActivate(WidgetTester t, Key key, String source) async {
  final adapter = find.byWidgetPredicate(
    (w) => w is StarBridgeIconAction && w.controlKey == key,
  );
  final widget = t.widget<StarBridgeIconAction>(adapter);
  if (source == 'reader') {
    // The suffix combines the helpful hint with the action label in one node.
    final target = find.bySemanticsLabel(
      RegExp('${RegExp.escape(widget.label)}\$'),
    );
    if (widget.onActivate == null) {
      expect(
        exposedNodes(t)
            .where((n) => n.getSemanticsData().label.endsWith(widget.label))
            .every((n) => !n.getSemanticsData().hasAction(SemanticsAction.tap)),
        true,
      );
    } else {
      expect(
        exposedNodes(t).where(
          (n) =>
              n.getSemanticsData().label.endsWith(widget.label) &&
              n.getSemanticsData().hasAction(SemanticsAction.tap),
        ),
        hasLength(1),
      );
      await semanticTap(t, target.last);
    }
  } else if (source == 'keyboard') {
    final icon = find.descendant(
      of: adapter,
      matching: find.byType(StarBridgeIcon),
    );
    Focus.of(t.element(icon)).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await t.tap(find.byKey(key), warnIfMissed: widget.onActivate != null);
  }
  await t.pump();
  await t.pump();
}

class Port extends base.Port {
  Port({this.name = '当前测试预设'});
  String name;
  final runtimeCalls = <OverlayRuntimeAction>[];
  Completer<OverlayRuntimeSnapshot>? heldRuntime;
  String runtimeState = 'closed';
  @override
  OverlayWorkspaceSnapshot get snapshot {
    final s = super.snapshot;
    return OverlayWorkspaceSnapshot.available(
      revision: s.revision!,
      storageState: s.storageState!,
      activePresetId: s.activePresetId!,
      renderMode: s.renderMode!,
      appearances: s.appearances,
      hotkey: s.hotkey!,
      settings: s.settings!,
      layout: s.layout,
      sourcePresetsEnabled: s.sourcePresetsEnabled,
      presets: [
        for (final p in s.presets)
          OverlayWorkspacePreset(
            id: p.id,
            name: p.isActive ? name : p.name,
            isActive: p.isActive,
            storageState: p.storageState,
            settings: p.settings,
            layout: p.layout,
            sources: p.sources,
          ),
      ],
    );
  }

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    if (pending == null &&
        failure == null &&
        mutation.kind == OverlayWorkspaceMutationKind.renamePreset) {
      name = mutation.name!;
    }
    return super.apply(mutation, expectedRevision: expectedRevision);
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async {
    runtimeCalls.add(action);
    return heldRuntime?.future ?? runtime(runtimeState);
  }
}

OverlayRuntimeSnapshot runtime(String state) => OverlayRuntimeSnapshot(
  windowState: state,
  isVisible: state == 'open',
  appliedRevision: 1,
  hotkeyState: 'registered',
  followGameState: 'manual',
  requestedSkin: 'Default',
  effectiveSkin: 'Default',
  usedFallbackSkin: false,
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite runtime and hotkey large text fit narrow panels', (
      t,
    ) async {
      size(t, const Size(800, 1000));
      final port = Port();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      final frame = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: frame,
          child: scopedApp(
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Center(
                child: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        OverlayWorkspaceRuntimeCard(
                          projection: module.projection.value,
                          onAction: () {},
                        ),
                        OverlayWorkspaceHotkeyCard(
                          hotkey: module.projection.value.hotkey!,
                          onBindingChanged: (_) {},
                          onEnabledChanged: (_) {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            suite,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3S'] == '1') {
        await t.runAsync(() async {
          final image =
              await (frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            final dir = Directory('build/reviews/interaction-batch3s');
            await dir.create(recursive: true);
            await File('${dir.path}/${suite.name}-controls-large-text.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await t.pumpWidget(const SizedBox());
    });
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite inline rename $source keeps the typed name on failure and retries once',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = Port();
            final (module, _) = await base.mount(
              t,
              port,
              suite,
              compact: false,
            );
            module.updateSetting('showNotice', false);
            await t.pumpAndSettle();
            port.writes.clear(); // the edit saved on its own
            port.failure = OverlaySettingsFailure.writeFailed;
            final field = find.byKey(const Key('overlay-active-preset-name'));
            await t.enterText(field, '深空测试');
            await t.pump();
            await iconActivate(
              t,
              const Key('overlay-active-preset-rename'),
              source,
            );
            await t.pumpAndSettle();
            expect(port.writes, hasLength(1));
            expect(port.writes.single.name, '深空测试');
            expect(t.widget<TextField>(field).controller!.text, '深空测试');
            expect(module.projection.value.dirty, false);
            expect(module.projection.value.settings!['showNotice'], false);
            port.failure = null;
            await iconActivate(
              t,
              const Key('overlay-active-preset-rename'),
              source,
            );
            await t.pumpAndSettle();
            expect(port.writes, hasLength(2));
            expect(
              module.projection.value.snapshot!.presets.first.name,
              '深空测试',
            );
            expect(module.projection.value.dirty, false);
            await iconActivate(
              t,
              const Key('overlay-active-preset-rename'),
              source,
            );
            expect(port.writes, hasLength(2));
            await t.pumpWidget(const SizedBox());
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite hotkey $source keeps capture, cancel and staged changes',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            size(t, const Size(800, 650));
            var binding = 'Alt+O', enabled = true;
            final changed = <String>[];
            late StateSetter rebuild;
            await t.pumpWidget(
              scopedApp(
                StatefulBuilder(
                  builder: (_, setState) {
                    rebuild = setState;
                    return OverlayWorkspaceHotkeyCard(
                      hotkey: OverlayWorkspaceHotkey(
                        binding: binding,
                        enabled: enabled,
                        runtimeState: 'pending',
                      ),
                      onBindingChanged: (value) => rebuild(() {
                        binding = value;
                        changed.add(value);
                      }),
                      onEnabledChanged: (value) =>
                          rebuild(() => enabled = value),
                    );
                  },
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await activate(
              t,
              find.byKey(const Key('overlay-hotkey-record')),
              source,
            );
            await t.pump();
            expect(
              find.byKey(const Key('overlay-hotkey-capturing')),
              findsOneWidget,
            );
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pumpAndSettle();
            expect(changed, isEmpty);
            await activate(
              t,
              find.byKey(const Key('overlay-hotkey-record')),
              source,
            );
            await t.pump();
            await t.sendKeyEvent(LogicalKeyboardKey.keyA);
            await t.pump();
            expect(changed, isEmpty);
            await t.sendKeyEvent(LogicalKeyboardKey.f8);
            await t.pumpAndSettle();
            expect(changed, ['F8']);
            await activate(
              t,
              find.byKey(const Key('overlay-hotkey-reset')),
              source,
            );
            await t.pumpAndSettle();
            expect(changed, ['F8', 'Alt+O']);
            final tile = find.byKey(const Key('overlay-hotkey-enabled'));
            if (source == 'reader') {
              await semanticTap(
                t,
                find.bySemanticsLabel(t.widget<StarBridgeSwitch>(tile).label),
              );
            } else if (source == 'keyboard') {
              final native = find.descendant(
                of: tile,
                matching: find.byType(Switch),
              );
              final custom = find.descendant(
                of: tile,
                matching: find.byType(SuiteSwitch),
              );
              final focus = suite == InteractionSuite.standard
                  ? t.widget<Switch>(native).focusNode!
                  : t.widget<SuiteSwitch>(custom).focusNode!;
              focus.requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.space);
            } else {
              await t.tap(find.text(t.widget<StarBridgeSwitch>(tile).label));
            }
            await t.pumpAndSettle();
            expect(enabled, false);
            await t.pumpWidget(const SizedBox());
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets('$suite old rename response cannot alter a new module editor', (
      t,
    ) async {
      final old = Port()..pending = Completer();
      final (oldModule, state) = await base.mount(
        t,
        old,
        suite,
        compact: false,
      );
      final field = find.byKey(const Key('overlay-active-preset-name'));
      await t.enterText(field, '旧账户提交');
      await t.pump();
      await iconActivate(
        t,
        const Key('overlay-active-preset-rename'),
        'keyboard',
      );
      expect(old.writes, hasLength(1));
      final next = Port(name: '新账户预设');
      final nextModule = OverlayWorkspaceModule(next);
      addTearDown(nextModule.dispose);
      await nextModule.refresh();
      await t.pumpWidget(
        base.Harness(nextModule, suite, compact: false, key: state.widget.key),
      );
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).controller!.text, '新账户预设');
      await t.enterText(field, '新账户待编辑');
      await t.pump();
      old.pending!.complete(
        OverlayWorkspaceWriteResult.completed(old.snapshot),
      );
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).controller!.text, '新账户待编辑');
      expect(next.writes, isEmpty);
      expect(oldModule.projection.value.busy, false);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
    testWidgets(
      '$suite leaving during inline rename drops only late UI feedback',
      (t) async {
        final port = Port()..pending = Completer();
        final (module, _) = await base.mount(t, port, suite, compact: false);
        await t.enterText(
          find.byKey(const Key('overlay-active-preset-name')),
          '离开前的提交',
        );
        await t.pump();
        await iconActivate(
          t,
          const Key('overlay-active-preset-rename'),
          'keyboard',
        );
        expect(port.writes, hasLength(1));
        await t.pumpWidget(const SizedBox());
        port.pending!.complete(
          OverlayWorkspaceWriteResult.completed(port.snapshot),
        );
        await t.pumpAndSettle();
        expect(port.writes, hasLength(1));
        expect(module.projection.value.busy, false);
        expect(t.takeException(), isNull);
      },
    );
    for (final compact in [false, true]) {
      testWidgets(
        '$suite runtime $compact preserves latest state and blocks duplicate commands',
        (t) async {
          size(t, const Size(1100, 750));
          final port = Port();
          final module = OverlayWorkspaceModule(port);
          addTearDown(module.dispose);
          await module.refresh();
          var reduce = false;
          late StateSetter rebuild;
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, setState) {
                rebuild = setState;
                return scopedApp(
                  ValueListenableBuilder<OverlayWorkspaceProjection>(
                    valueListenable: module.projection,
                    builder: (_, p, _) => OverlayWorkspaceRuntimeCard(
                      projection: p,
                      compact: compact,
                      onAction: () => module.openRuntime('zh-CN'),
                    ),
                  ),
                  suite,
                  reduce: reduce,
                );
              },
            ),
          );
          await t.pumpAndSettle();
          port.runtimeCalls.clear();
          port.heldRuntime = Completer();
          await activate(
            t,
            find.byKey(const Key('overlay-runtime-action')),
            'keyboard',
          );
          expect(port.runtimeCalls, [OverlayRuntimeAction.open]);
          await t.tap(
            find.byKey(const Key('overlay-runtime-action')),
            warnIfMissed: false,
          );
          await t.pump();
          expect(port.runtimeCalls, hasLength(1));
          rebuild(() => reduce = true);
          await t.pump();
          await t.pump();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          port.heldRuntime!.complete(runtime('failed'));
          await t.pumpAndSettle();
          expect(module.projection.value.runtime.windowState, 'failed');
          expect(module.projection.value.runtimeBusy, false);
          await t.pumpWidget(const SizedBox());
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
