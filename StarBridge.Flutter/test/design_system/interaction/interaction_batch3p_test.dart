import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_sources.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_source_binding_field.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_settings_dialog.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3b_test.dart' show semanticTap;
import 'interaction_batch2_test.dart' show pixels;
import 'interaction_batch3o_test.dart' as previous;
import 'interaction_batch3m_test.dart' show activate;

class ScenePort implements OverlayScenePort {
  OverlaySceneState state = directory();
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OverlaySceneState> read() async => state;
  @override
  Future<OverlaySceneState> select(int revision, String mode, String? code) =>
      throw StateError('A display binding must not select the account source.');
  @override
  Future<OverlaySceneState> focusCommunity(String code) => read();
  @override
  Future<OverlaySceneState> focusFleet() => focusCommunity('');
  @override
  void close() {}
}

OverlaySceneState directory({
  String owner = 'fixture-owner',
  int generation = 1,
  bool available = true,
  bool failure = false,
  List<OverlaySceneTarget> targets = const [
    OverlaySceneTarget('one', '测试组织一'),
    OverlaySceneTarget('two', '测试组织二'),
  ],
}) => OverlaySceneState(
  available: available,
  failure: failure,
  sourceOwnerKey: owner,
  contextGeneration: generation,
  targets: targets,
);

class FieldHarness extends StatefulWidget {
  const FieldHarness(this.suite, this.scenes, {super.key});
  final InteractionSuite suite;
  final OverlaySceneController scenes;
  @override
  State<FieldHarness> createState() => FieldState();
}

class FieldState extends State<FieldHarness> {
  var value = const OverlaySourceBinding.room();
  bool enabled = true, reduce = false, show = true;
  final changes = <OverlaySourceBinding>[];
  void change(VoidCallback update) => setState(update);
  @override
  Widget build(BuildContext context) => scopedApp(
    Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SizedBox(
          width: 380,
          child: !show
              ? const Text('已离开')
              : OverlaySourceBindingField(
                  value: value,
                  scenes: widget.scenes,
                  presetBinding: true,
                  onChanged: enabled
                      ? (next) => change(() {
                          changes.add(next);
                          value = next;
                        })
                      : null,
                ),
        ),
      ),
    ),
    widget.suite,
    reduce: reduce,
  );
}

Future<(ScenePort, OverlaySceneController, FieldState)> mountField(
  WidgetTester t,
  InteractionSuite suite, {
  GlobalKey? frame,
}) async {
  size(t, const Size(900, 650));
  final port = ScenePort();
  final scenes = OverlaySceneController(port, autoStart: false);
  addTearDown(scenes.dispose);
  await scenes.refresh();
  final key = GlobalKey<FieldState>();
  final harness = FieldHarness(suite, scenes, key: key);
  await t.pumpWidget(
    frame == null ? harness : RepaintBoundary(key: frame, child: harness),
  );
  await t.pumpAndSettle();
  return (port, scenes, key.currentState!);
}

Finder get trigger => find.byKey(const Key('overlay-source-binding-trigger'));
Finder choice(OverlaySourceBinding value) =>
    find.byKey(ValueKey<Object>(value));

Future<void> open(WidgetTester t, String source) async {
  if (source == 'pointer') {
    await t.tap(trigger);
  } else if (source == 'reader') {
    await semanticTap(t, find.bySemanticsLabel(RegExp('^固定来源（可选） ·')));
  } else {
    t
        .widget<StarBridgeActionRow>(
          find.ancestor(
            of: trigger,
            matching: find.byType(StarBridgeActionRow),
          ),
        )
        .focusNode!
        .requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await t.pump();
  await t.pump();
}

Future<void> select(
  WidgetTester t,
  InteractionSuite suite,
  OverlaySourceBinding value,
  String source,
  String label,
) async {
  final target = choice(value);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'reader') {
    await semanticTap(t, find.bySemanticsLabel(label));
  } else {
    final node = suite == InteractionSuite.standard
        ? t.widget<MenuItemButton>(target).focusNode!
        : t.widget<SuitePressable>(target).focusNode!;
    node.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await t.pump();
  await t.pump();
}

Future<void> capture(WidgetTester t, GlobalKey frame, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3P'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final directory = Directory('build/reviews/interaction-batch3p');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite $source source selection retains value and origin', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        try {
          final frame = GlobalKey();
          final (_, _, state) = await mountField(t, suite, frame: frame);
          await open(t, source);
          final transition = t.widget<SuiteSurfaceTransition>(
            find.byType(SuiteSurfaceTransition),
          );
          expect(
            transition.animation.value,
            source == 'pointer' ? lessThan(1) : 1,
          );
          await t.pumpAndSettle();
          expect(
            t
                .getSemantics(find.bySemanticsLabel('当前房间'))
                .getSemanticsData()
                .flagsCollection
                .isSelected,
            Tristate.isTrue,
          );
          if (source == 'pointer') {
            await capture(t, frame, '${suite.name}-sources');
          }
          await select(
            t,
            suite,
            const OverlaySourceBinding.automatic(),
            source,
            '自动',
          );
          expect(state.value, const OverlaySourceBinding.automatic());
          expect(state.changes, [const OverlaySourceBinding.automatic()]);
          if (source != 'pointer') {
            expect(find.byType(SuiteSurfaceTransition), findsNothing);
          }
          await t.pumpAndSettle();
          await open(t, 'keyboard');
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(find.byType(SuiteSurfaceTransition), findsNothing);
          expect(
            t
                .widget<StarBridgeActionRow>(find.byType(StarBridgeActionRow))
                .focusNode!
                .hasFocus,
            true,
          );
          expect(state.changes, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }

    testWidgets(
      '$suite removed directory item cannot execute retained menu action',
      (t) async {
        final (port, scenes, state) = await mountField(t, suite);
        await open(t, 'keyboard');
        final target = choice(
          OverlaySourceBinding.community('one', 'fixture-owner'),
        );
        final VoidCallback stale = suite == InteractionSuite.standard
            ? t.widget<MenuItemButton>(target).onPressed!
            : () => t.widget<SuitePressable>(target).onActivate!(
                InteractionSource.pointer,
              );
        // Capture the suite callback before its element is removed.
        final suiteAction = suite == InteractionSuite.standard
            ? null
            : t.widget<SuitePressable>(target).onActivate;
        port.state = directory(
          targets: const [OverlaySceneTarget('two', '新名称')],
        );
        await scenes.refresh();
        await t.pump();
        await t.pump();
        if (suiteAction == null) {
          stale();
        } else {
          suiteAction(InteractionSource.pointer);
        }
        await t.pump();
        expect(state.changes, isEmpty);
        expect(find.text('测试组织一'), findsNothing);
        expect(find.text('新名称'), findsOneWidget);
        await select(
          t,
          suite,
          OverlaySourceBinding.community('two', 'fixture-owner'),
          'keyboard',
          '新名称',
        );
        expect(
          state.changes.single,
          OverlaySourceBinding.community('two', 'fixture-owner'),
        );
        expect(t.takeException(), isNull);
      },
    );

    for (final invalidation in [
      'owner',
      'generation',
      'failure',
      'unavailable',
    ]) {
      testWidgets(
        '$suite $invalidation invalidation removes old directory immediately',
        (t) async {
          final (port, scenes, state) = await mountField(t, suite);
          await open(t, 'pointer');
          await t.pump(const Duration(milliseconds: 40));
          port.state = directory(
            owner: invalidation == 'owner' ? 'new-owner' : 'fixture-owner',
            generation: invalidation == 'generation' ? 2 : 1,
            failure: invalidation == 'failure',
            available: invalidation != 'unavailable',
          );
          await scenes.refresh();
          await t.pump();
          await t.pump();
          expect(find.byType(SuiteSurfaceTransition), findsNothing);
          expect(state.changes, isEmpty);
          await open(t, 'keyboard');
          expect(choice(const OverlaySourceBinding.room()), findsOneWidget);
          await select(
            t,
            suite,
            const OverlaySourceBinding.room(),
            'keyboard',
            '当前房间',
          );
          expect(state.changes, [const OverlaySourceBinding.room()]);
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$suite unavailable selection stays explicit; disable and leave close menu',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          final (_, _, state) = await mountField(t, suite);
          final unavailable = OverlaySourceBinding.community(
            'private-code',
            'old-owner',
          );
          state.change(() => state.value = unavailable);
          await t.pump();
          await open(t, 'keyboard');
          final node = t.getSemantics(find.bySemanticsLabel('所选组织暂不可用'));
          expect(node.getSemanticsData().hasAction(SemanticsAction.tap), false);
          expect(find.textContaining('private-code'), findsNothing);
          expect(find.textContaining('old-owner'), findsNothing);
          state.change(() => state.enabled = false);
          await t.pump();
          await t.pump();
          expect(find.byType(SuiteSurfaceTransition), findsNothing);
          expect(state.value, unavailable);
          expect(state.changes, isEmpty);
          state.change(() => state.enabled = true);
          await t.pump();
          await open(t, 'pointer');
          await t.pump(const Duration(milliseconds: 30));
          state.change(() => state.reduce = true);
          await t.pump();
          await t.pump();
          expect(
            t
                .widget<SuiteSurfaceTransition>(
                  find.byType(SuiteSurfaceTransition),
                )
                .animation
                .value,
            1,
          );
          state.change(() => state.show = false);
          await t.pump();
          await t.pumpAndSettle();
          expect(find.byType(SuiteSurfaceTransition), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source whole switch row is a single instant-or-animated target',
        (t) async {
          size(t, const Size(900, 650));
          final semantics = t.ensureSemantics();
          var value = false;
          final calls = <bool>[];
          try {
            await t.pumpWidget(
              scopedApp(
                Center(
                  child: SizedBox(
                    width: 440,
                    child: StatefulBuilder(
                      builder: (context, update) => StarBridgeSwitch.tile(
                        label: '自动切换测试',
                        subtitle: '只改变草稿，保存后生效',
                        value: value,
                        onChanged: (next) => update(() {
                          calls.add(next);
                          value = next;
                        }),
                      ),
                    ),
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            expect(find.bySemanticsLabel('自动切换测试'), findsOneWidget);
            final node = t.getSemantics(find.bySemanticsLabel('自动切换测试'));
            expect(node.getSemanticsData().hint, '只改变草稿，保存后生效');
            expect(node.rect.width, 440);
            for (var i = 0; i < 3; i++) {
              if (source == 'reader') {
                await semanticTap(t, find.bySemanticsLabel('自动切换测试'));
              } else if (source == 'keyboard') {
                final focus = suite == InteractionSuite.standard
                    ? t.widget<Switch>(find.byType(Switch)).focusNode!
                    : t
                          .widget<SuiteSwitch>(find.byType(SuiteSwitch))
                          .focusNode!;
                focus.requestFocus();
                await t.pump();
                await t.sendKeyEvent(LogicalKeyboardKey.space);
              } else {
                await t.tap(find.text('自动切换测试'));
              }
              await t.pump();
              await t.pump();
              expect(calls.length, i + 1);
              if (source != 'pointer') {
                expect(t.binding.hasScheduledFrame, false);
              }
            }
            expect(calls, [true, false, true]);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite rapid row toggles paint feedback then live reduce and disable settle',
      (t) async {
        size(t, const Size(900, 650));
        var value = false, enabled = true, reduce = false;
        var calls = 0;
        late StateSetter update;
        final frame = GlobalKey();
        await t.pumpWidget(
          StatefulBuilder(
            builder: (context, set) {
              update = set;
              return scopedApp(
                Center(
                  child: RepaintBoundary(
                    key: frame,
                    child: SizedBox(
                      width: 440,
                      child: StarBridgeSwitch.tile(
                        label: '自动切换测试',
                        subtitle: '只改变草稿，保存后生效',
                        value: value,
                        onChanged: !enabled
                            ? null
                            : (next) => set(() {
                                calls++;
                                value = next;
                              }),
                      ),
                    ),
                  ),
                ),
                suite,
                reduce: reduce,
              );
            },
          ),
        );
        await t.pumpAndSettle();
        for (var i = 0; i < 4; i++) {
          await t.tap(find.text('自动切换测试'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 35));
          final during = await pixels(t, frame);
          await t.pump(const Duration(milliseconds: 35));
          expect(during, isNot(await pixels(t, frame)));
          expect(calls, i + 1);
        }
        await t.tap(find.text('自动切换测试'));
        await t.pump();
        update(() => reduce = true);
        await t.pump();
        await t.pump();
        expect(t.binding.hasScheduledFrame, false);
        update(() => enabled = false);
        await t.pumpAndSettle();
        await t.tap(find.text('自动切换测试'), warnIfMissed: false);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(calls, 5);
        await capture(t, frame, '${suite.name}-switch');
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite source and automatic switching remain drafts across save failure',
      (t) async {
        final port = previous.Port();
        final frame = GlobalKey();
        final (module, _) = await previous.mount(t, port, suite, frame: frame);
        await activate(
          t,
          find.byKey(const Key('overlay-preset-settings-entry')),
          'keyboard',
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('overlay-preset-auto-switch')));
        await t.pumpAndSettle();
        expect(
          t.widget<StarBridgeSwitch>(find.byType(StarBridgeSwitch)).value,
          true,
        );
        await open(t, 'keyboard');
        await select(
          t,
          suite,
          const OverlaySourceBinding.follow(),
          'keyboard',
          '跟随账号',
        );
        await t.pumpAndSettle();
        final disabled = t.widget<StarBridgeSwitch>(
          find.byType(StarBridgeSwitch),
        );
        expect(disabled.value, false);
        expect(disabled.onChanged, isNull);
        expect(port.writes, isEmpty);
        await open(t, 'keyboard');
        await select(
          t,
          suite,
          const OverlaySourceBinding.room(),
          'keyboard',
          '当前房间',
        );
        await t.pumpAndSettle();
        expect(
          t.widget<StarBridgeSwitch>(find.byType(StarBridgeSwitch)).value,
          false,
        );
        await t.tap(find.byKey(const Key('overlay-preset-auto-switch')));
        await t.pumpAndSettle();
        port.failure = OverlaySettingsFailure.writeFailed;
        await activate(
          t,
          find.byKey(const Key('overlay-preset-settings-save')),
          'keyboard',
        );
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('overlay-preset-settings-error')),
          findsOneWidget,
        );
        await capture(t, frame, '${suite.name}-settings-failure');
        expect(
          t.widget<StarBridgeSwitch>(find.byType(StarBridgeSwitch)).value,
          true,
        );
        expect(
          port.writes.single.sources!.binding,
          const OverlaySourceBinding.room(),
        );
        expect(port.writes.single.sources!.autoSwitch, true);
        expect(
          module.projection.value.snapshot!.presets.first.sources!.autoSwitch,
          false,
        );
        port.failure = null;
        await activate(
          t,
          find.byKey(const Key('overlay-preset-settings-save')),
          'keyboard',
        );
        await t.pumpAndSettle();
        expect(port.writes, hasLength(2));
        expect(find.byType(OverlayPresetSettingsDialog), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('$suite preset settings stays usable at 200 percent text', (
      t,
    ) async {
      final port = previous.Port();
      await previous.mount(t, port, suite);
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpAndSettle();
      await activate(
        t,
        find.byKey(const Key('overlay-preset-settings-entry')),
        'keyboard',
      );
      await t.pumpAndSettle();
      await t.ensureVisible(trigger);
      await open(t, 'keyboard');
      await select(
        t,
        suite,
        const OverlaySourceBinding.follow(),
        'keyboard',
        '跟随账号',
      );
      await t.pumpAndSettle();
      expect(
        t.widget<StarBridgeSwitch>(find.byType(StarBridgeSwitch)).onChanged,
        isNull,
      );
      await t.ensureVisible(
        find.byKey(const Key('overlay-preset-settings-save')),
      );
      expect(t.takeException(), isNull);
      expect(port.writes, isEmpty);
    });
  }
}
