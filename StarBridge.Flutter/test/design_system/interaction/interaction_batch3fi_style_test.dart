import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module_style_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import 'interaction_batch3fc_visibility_test.dart' show visibilityFrames;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

const styleItem = OverlayWorkspaceLayoutItem(
  key: 'Notice',
  x: .1,
  y: .2,
  width: .6,
  height: .2,
  horizontalAnchor: 'Left',
  verticalAnchor: 'Top',
  isLocked: false,
  textOpacity: .6,
  backgroundOpacity: .4,
  decorationOpacity: .5,
);
const opacityFields = [
  ('text', '文字透明度', .15, 17, 'eventNotificationTextOpacity'),
  ('background', '背景透明度', 0.0, 20, 'eventNotificationBackgroundOpacity'),
  ('decoration', '外观装饰透明度', 0.0, 20, 'eventNotificationDecorationOpacity'),
];

OverlayWorkspaceSettings styleSettings() => settings({
  'eventNotificationTextOpacity': .6,
  'eventNotificationBackgroundOpacity': .4,
  'eventNotificationDecorationOpacity': .5,
});

class StyleChange {
  StyleChange(this.item, this.coalesce)
    : source = currentStarBridgeActivationSource;
  final OverlayWorkspaceLayoutItem item;
  final bool coalesce;
  final InteractionSource source;
}

class SettingChange {
  SettingChange(this.field, this.value)
    : source = currentStarBridgeActivationSource;
  final String field;
  final Object? value;
  final InteractionSource source;
}

class StyleProbe {
  StyleProbe(this.suite, {this.module});
  InteractionSuite suite;
  final OverlayWorkspaceModule? module;
  bool reduce = false, light = false;
  String group = 'notice';
  var layout = [styleItem];
  var values = styleSettings();
  final layoutCalls = <StyleChange>[];
  final settingCalls = <SettingChange>[];
  late StateSetter update;

  Widget controls(
    List<OverlayWorkspaceLayoutItem> items,
    OverlayWorkspaceSettings projected,
  ) => OverlayWorkspaceModuleStyleControls(
    group: group,
    layout: items,
    settings: projected,
    onLayoutChanged: (item, coalesce) {
      layoutCalls.add(StyleChange(item, coalesce));
      final owner = module;
      if (owner != null) {
        owner.updateLayoutItem(item, coalesce: coalesce);
      } else {
        update(
          () => layout = [
            for (final old in layout) old.key == item.key ? item : old,
          ],
        );
      }
    },
    onSettingChanged: (field, value) {
      settingCalls.add(SettingChange(field, value));
      final owner = module;
      if (owner != null) {
        owner.updateSetting(field, value);
      } else {
        update(() => values = settings({...values.toMap(), field: value}));
      }
    },
  );

  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        Semantics(
          explicitChildNodes: true,
          child: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: module == null
                  ? controls(layout, values)
                  : ValueListenableBuilder<OverlayWorkspaceProjection>(
                      valueListenable: module!.projection,
                      builder: (_, projection, _) =>
                          controls(projection.layout, projection.settings!),
                    ),
            ),
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Finder opacity(String kind, {String module = 'Notice'}) => find.descendant(
  of: find.byKey(Key('overlay-module-$kind-opacity-$module')),
  matching: find.byType(StarBridgeSlider),
);
Finder sliderFace(Finder adapter) => find.descendant(
  of: adapter,
  matching: find.byWidgetPredicate((w) => w is Slider || w is SuiteSlider),
);

Future<void> styleTab(WidgetTester t, FocusNode node, Finder target) async {
  expect(node.canRequestFocus, isTrue);
  FocusScope.of(t.element(target)).unfocus();
  await t.pump();
  await t.pump();
  for (var i = 0; !node.hasPrimaryFocus && i < 50; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.pump();
  }
  expect(
    node.hasPrimaryFocus,
    isTrue,
    reason: 'target=$node\n${FocusManager.instance.toStringDeep()}',
  );
}

void styleReader(WidgetTester t, String label, ui.SemanticsAction action) {
  final nodes = exposedNodes(t).where((node) {
    final data = node.getSemanticsData();
    return data.label == label && data.hasAction(action);
  }).toList();
  expect(nodes, hasLength(1), reason: 'one exposed $action target for $label');
  t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    nodes.single.id,
    action,
  );
}

Future<void> styleLock(WidgetTester t, String input) async {
  final adapter = find.byType(StarBridgeSwitch);
  expect(adapter, findsOneWidget);
  if (input == 'reader') {
    styleReader(t, '锁定位置与大小', ui.SemanticsAction.tap);
  } else if (input == 'keyboard') {
    final row = find.descendant(
      of: adapter,
      matching: find.byType(SuitePressable),
    );
    final node = row.evaluate().isNotEmpty
        ? t.widget<SuitePressable>(row).focusNode!
        : t
              .widget<SuiteSwitch>(
                find.descendant(
                  of: adapter,
                  matching: find.byType(SuiteSwitch),
                ),
              )
              .focusNode!;
    await styleTab(t, node, adapter);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    // The native tile is deliberately decorative inside its one row owner.
    // Hit that real row, not the ignored Text rendered by the native child.
    final row = find.descendant(
      of: adapter,
      matching: find.byType(SuitePressable),
    );
    final target = row.evaluate().isNotEmpty
        ? row
        : find.descendant(
            of: adapter,
            matching: find.byWidgetPredicate(
              (widget) => widget is GestureDetector && widget.child is ListTile,
            ),
          );
    expect(target, findsOneWidget);
    await t.tap(target);
  }
  await t.pump();
  await t.pump();
}

Future<void> styleOpacity(WidgetTester t, Finder adapter, String input) async {
  final control = t.widget<StarBridgeSlider>(adapter);
  final face = sliderFace(adapter);
  expect(face, findsOneWidget);
  await t.ensureVisible(face);
  if (input == 'reader') {
    styleReader(t, control.semanticLabel!, ui.SemanticsAction.increase);
  } else if (input == 'keyboard') {
    final node = switch (t.widget(face)) {
      Slider slider => slider.focusNode!,
      SuiteSlider slider => slider.focusNode!,
      _ => throw StateError('Missing mounted slider face'),
    };
    await styleTab(t, node, face);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  } else {
    final box = t.getRect(face);
    final pad = t.widget(face) is Slider ? 24.0 : 9.0;
    final fraction =
        (control.value - control.min) / (control.max - control.min);
    final start = Offset(
      box.left + pad + (box.width - pad * 2) * fraction,
      box.center.dy,
    );
    final gesture = await t.startGesture(start);
    await t.pump();
    await gesture.moveBy(const Offset(45, 0));
    await t.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(45, 0));
    await t.pump(const Duration(milliseconds: 16));
    await gesture.up();
  }
  await t.pump();
  await t.pump();
}

class StyleWrite {
  StyleWrite(this.mutation, this.revision);
  final OverlayWorkspaceMutation mutation;
  final int revision;
  final reply = Completer<OverlayWorkspaceWriteResult>();
}

class StylePort implements OverlayWorkspacePort {
  int revision = 7;
  var layout = [styleItem];
  var values = styleSettings();
  final writes = <StyleWrite>[];
  OverlayWorkspaceSnapshot get snapshot => OverlayWorkspaceSnapshot.available(
    revision: revision,
    storageState: 'ready',
    activePresetId: 'one',
    renderMode: 'NativeComposition',
    appearances: const [],
    presets: const [],
    hotkey: const OverlayWorkspaceHotkey(
      binding: 'Alt+O',
      enabled: true,
      runtimeState: 'registered',
    ),
    settings: values,
    layout: layout,
  );
  @override
  Future<OverlayWorkspaceSnapshot> read() async => snapshot;
  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) {
    final write = StyleWrite(mutation, expectedRevision);
    writes.add(write);
    return write.reply.future;
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async => const OverlayRuntimeSnapshot(
    windowState: 'closed',
    isVisible: false,
    appliedRevision: 7,
    hotkeyState: 'registered',
    followGameState: 'manual',
    requestedSkin: 'Default',
    effectiveSkin: 'Default',
    usedFallbackSkin: false,
  );
  @override
  Future<void> close() async {}
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3fi $suite $input original layout callbacks, limits and live settings',
        (t) async {
          size(t, const Size(1000, 950));
          final semantics = t.ensureSemantics();
          final p = StyleProbe(suite);
          try {
            await t.pumpWidget(p.app());
            await visibilityFrames(t);
            expect(
              find.byKey(const Key('overlay-module-style-Notice')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('overlay-module-lock-Notice')),
              findsOneWidget,
            );
            final origin = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            await styleLock(t, input);
            expect(p.layout.single.isLocked, isTrue);
            expect(p.layoutCalls, hasLength(1));
            expect(p.layoutCalls.single.coalesce, isFalse);
            expect(p.layoutCalls.single.source, origin);
            for (final field in opacityFields) {
              final adapter = opacity(field.$1);
              final before = t.widget<StarBridgeSlider>(adapter);
              expect(before.min, field.$3);
              expect(before.max, 1);
              expect(before.divisions, field.$4);
              expect(before.semanticLabel, field.$2);
              final previousCalls = p.layoutCalls.length;
              await styleOpacity(t, adapter, input);
              final after = t.widget<StarBridgeSlider>(adapter);
              expect(after.value, greaterThan(before.value));
              if (input != 'pointer') {
                expect(after.value, closeTo(before.value + .05, 1e-8));
              }
              expect(after.value, lessThanOrEqualTo(1));
              expect(
                after.valueLabel!(after.value),
                '${(after.value * 100).round()}%',
              );
              final additions = p.layoutCalls.skip(previousCalls).toList();
              expect(additions, isNotEmpty);
              expect(
                additions.every((e) => e.coalesce && e.source == origin),
                isTrue,
              );
              expect(p.layout.single.x, styleItem.x);
              expect(p.layout.single.height, styleItem.height);
              expect(p.layout.single.isLocked, isTrue);
            }
            expect(p.settingCalls, isEmpty);
            final projected = p.layout.single.toMap();
            final count = p.layoutCalls.length;
            p.update(() {
              p.reduce = true;
              p.light = true;
            });
            await t.pump();
            await t.pump();
            expect(p.layout.single.toMap(), projected);
            expect(p.layoutCalls, hasLength(count));
            await styleLock(t, input);
            expect(p.layout.single.isLocked, isFalse);
            expect(p.layoutCalls.last.coalesce, isFalse);
            expect(p.layoutCalls.last.source, origin);
            // A suite change must not become another domain operation.
            final last = p.layout.single.toMap();
            p.update(
              () => p.suite = suite == InteractionSuite.glow
                  ? InteractionSuite.scan
                  : InteractionSuite.glow,
            );
            await visibilityFrames(t);
            expect(p.layout.single.toMap(), last);
            expect(p.layoutCalls, hasLength(count + 1));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );

      testWidgets(
        '3fi $suite $input Events retains setting fields, never layout commands',
        (t) async {
          size(t, const Size(1000, 950));
          final semantics = t.ensureSemantics();
          final p = StyleProbe(suite)
            ..group = 'events'
            ..layout = [];
          try {
            await t.pumpWidget(p.app());
            await visibilityFrames(t);
            expect(find.byType(StarBridgeSwitch), findsNothing);
            expect(
              find.byKey(const Key('overlay-module-style-Events')),
              findsOneWidget,
            );
            final origin = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            for (final field in opacityFields) {
              final adapter = opacity(field.$1, module: 'Events');
              final before = t.widget<StarBridgeSlider>(adapter).value;
              final start = p.settingCalls.length;
              await styleOpacity(t, adapter, input);
              final after = t.widget<StarBridgeSlider>(adapter).value;
              expect(after, greaterThan(before));
              if (input != 'pointer') {
                expect(after, closeTo(before + .05, 1e-8));
              }
              final calls = p.settingCalls.skip(start).toList();
              expect(calls, isNotEmpty);
              expect(
                calls.every((e) => e.field == field.$5 && e.source == origin),
                isTrue,
              );
              expect(p.values[field.$5], after);
            }
            expect(p.layoutCalls, isEmpty);
            expect(p.layout, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '3fi $suite actual module undo, pending save, rejection and retry',
      (t) async {
        size(t, const Size(1000, 950));
        final port = StylePort();
        final module = OverlayWorkspaceModule(port);
        final p = StyleProbe(suite, module: module);
        // Answers the oldest open write; a success is stored as Host would.
        Future<void> reply({required bool ok}) async {
          final write = port.writes.firstWhere((w) => !w.reply.isCompleted);
          if (ok) {
            port.layout = write.mutation.layout!;
            port.values = write.mutation.settings!;
            port.revision++;
          }
          write.reply.complete(
            ok
                ? OverlayWorkspaceWriteResult.completed(port.snapshot)
                : const OverlayWorkspaceWriteResult.failed(
                    OverlaySettingsFailure.writeFailed,
                  ),
          );
          await visibilityFrames(t);
        }

        try {
          await module.initialize();
          await t.pumpWidget(p.app());
          await visibilityFrames(t);
          expect(module.projection.value.dirty, isFalse);
          await styleLock(t, 'pointer');
          expect(port.writes, hasLength(1));
          expect(port.writes.single.revision, 7);
          expect(port.writes.single.mutation.layout!.single.isLocked, isTrue);
          // While the lock is being written the drag stays editable; it is
          // written once, after the lock, never per sample.
          await styleOpacity(t, opacity('text'), 'pointer');
          final edited = module.projection.value.layout.single;
          expect(edited.isLocked, isTrue);
          expect(edited.textOpacity, greaterThan(styleItem.textOpacity));
          expect(module.projection.value.dirty, isTrue);
          expect(module.canUndo, isTrue);
          expect(port.writes, hasLength(1));
          await reply(ok: true);
          expect(port.writes, hasLength(2));
          expect(port.writes.last.revision, 8);
          expect(
            port.writes.last.mutation.layout!.single.toMap(),
            edited.toMap(),
          );
          await reply(ok: false);
          expect(
            module.projection.value.failure,
            OverlaySettingsFailure.writeFailed,
          );
          expect(module.projection.value.dirty, isTrue);
          expect(module.projection.value.layout.single.toMap(), edited.toMap());
          // Direct module save is the existing domain seam, not a synthetic UI save.
          final retried = module.save();
          await t.pump();
          expect(port.writes, hasLength(3));
          expect(port.writes.last.revision, 8);
          await reply(ok: true);
          expect(await retried, isTrue);
          expect(module.projection.value.snapshot!.revision, 9);
          expect(module.projection.value.dirty, isFalse);
          expect(module.projection.value.failure, isNull);
          expect(module.canUndo, isTrue, reason: 'history survives saves');
          module.undo();
          await t.pump();
          expect(
            module.projection.value.layout.single.toMap(),
            styleItem.copyWith(isLocked: true).toMap(),
            reason: 'all pointer samples coalesce into one history step',
          );
          await reply(ok: true);
          expect(
            port.layout.single.toMap(),
            styleItem.copyWith(isLocked: true).toMap(),
          );
          module.redo();
          await t.pump();
          await reply(ok: true);
          expect(port.layout.single.toMap(), edited.toMap());
          expect(module.projection.value.dirty, isFalse);
          p.update(() => p.group = 'events');
          await visibilityFrames(t);
          await styleOpacity(t, opacity('text', module: 'Events'), 'keyboard');
          expect(
            module.projection.value.settings!['eventNotificationTextOpacity'],
            closeTo(.65, 1e-8),
          );
          expect(p.settingCalls.single.field, 'eventNotificationTextOpacity');
          await reply(ok: true);
          expect(
            port.values['eventNotificationTextOpacity'],
            closeTo(.65, 1e-8),
          );
          expect(module.projection.value.dirty, isFalse);
          expect(port.writes.where((w) => !w.reply.isCompleted), isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          module.dispose();
        }
      },
    );

    testWidgets(
      '3fi $suite original empty mapping and missing items stay empty',
      (t) async {
        size(t, const Size(1000, 950));
        final p = StyleProbe(suite)..group = 'unmapped';
        try {
          await t.pumpWidget(p.app());
          await visibilityFrames(t);
          expect(find.byType(StarBridgeSlider), findsNothing);
          expect(find.byType(StarBridgeSwitch), findsNothing);
          for (final group in ['notice', 'fleetOverview', 'members', 'chat']) {
            p.update(() {
              p.group = group;
              p.layout = [];
            });
            await visibilityFrames(t);
            expect(find.byType(StarBridgeSlider), findsNothing);
            expect(find.byType(StarBridgeSwitch), findsNothing);
          }
          for (final (group, key) in [
            ('notice', 'Notice'),
            ('fleetOverview', 'Squads'),
            ('members', 'Members'),
            ('chat', 'Chat'),
          ]) {
            final item = OverlayWorkspaceLayoutItem.fromMap({
              ...styleItem.toMap(),
              'key': key,
            });
            p.update(() {
              p.group = group;
              p.layout = [item];
            });
            await visibilityFrames(t);
            expect(
              find.byKey(Key('overlay-module-style-$key')),
              findsOneWidget,
            );
            expect(find.byKey(Key('overlay-module-lock-$key')), findsOneWidget);
            // Overview, members and chat also show the shared calm display levels.
            expect(
              find.byType(StarBridgeSlider),
              findsNWidgets(
                const {'Squads', 'Members', 'Chat'}.contains(key) ? 5 : 3,
              ),
            );
          }
          expect(p.layoutCalls, isEmpty);
          expect(p.settingCalls, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
