import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction, CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_chat_sources_field.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_sources.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_scene_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_source_limit_notice.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp, route, dialogAction;
import 'interaction_batch3m_test.dart' show activate;
import 'interaction_batch3b_test.dart' show semanticTap;
import 'interaction_batch2_test.dart' show pixels;
import 'interaction_batch3p_test.dart' show ScenePort, directory;
import 'interaction_batch3o_test.dart' show Port;

class Harness extends StatefulWidget {
  const Harness(this.suite, this.scenes, {this.module, super.key});
  final InteractionSuite suite;
  final OverlaySceneController scenes;
  final OverlayWorkspaceModule? module;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  var value = OverlayPresetSources();
  bool reduce = false, enabled = true, show = true;
  int updates = 0;
  void change(VoidCallback update) => setState(update);
  @override
  Widget build(BuildContext context) => scopedApp(
    !show
        ? const Text('已离开')
        : Padding(
            padding: const EdgeInsets.all(24),
            child: widget.module != null
                ? OverlaySourceLimitNotice(
                    module: widget.module!,
                    scenes: widget.scenes,
                  )
                : SizedBox(
                    width: 420,
                    child: OverlayChatSourcesField(
                      value: value,
                      scenes: widget.scenes,
                      onChanged: !enabled
                          ? null
                          : (sources) => change(() {
                              updates++;
                              value = value.withChatSources(sources);
                            }),
                      onSingleChanged: !enabled
                          ? null
                          : (binding) => change(() {
                              updates++;
                              value = value.withModule(
                                OverlaySourceModule.chat,
                                binding,
                              );
                            }),
                    ),
                  ),
          ),
    widget.suite,
    reduce: reduce,
  );
}

Future<(ScenePort, OverlaySceneController, HarnessState)> mount(
  WidgetTester t,
  InteractionSuite suite, {
  OverlayWorkspaceModule? module,
  GlobalKey? frame,
}) async {
  size(t, const Size(1100, 900));
  final port = ScenePort()
    ..state = directory(
      targets: [
        for (var i = 0; i < 8; i++) OverlaySceneTarget('org-$i', '测试组织 $i'),
      ],
    );
  final scenes = OverlaySceneController(port, autoStart: false);
  addTearDown(scenes.dispose);
  await scenes.refresh();
  final key = GlobalKey<HarnessState>();
  final child = Harness(suite, scenes, module: module, key: key);
  await t.pumpWidget(
    frame == null ? child : RepaintBoundary(key: frame, child: child),
  );
  await t.pumpAndSettle();
  return (port, scenes, key.currentState!);
}

Future<void> check(
  WidgetTester t,
  InteractionSuite suite,
  Finder tile,
  String source,
) async {
  await t.ensureVisible(tile);
  if (source == 'reader') {
    final label = t.widget<StarBridgeCheckboxTile>(tile).label;
    await semanticTap(
      t,
      find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\$')),
    );
  } else if (source == 'keyboard') {
    final focus = suite == InteractionSuite.standard
        ? t
              .widget<Checkbox>(
                find.descendant(of: tile, matching: find.byType(Checkbox)),
              )
              .focusNode!
        : t
              .widget<SuiteCheckbox>(
                find.descendant(of: tile, matching: find.byType(SuiteCheckbox)),
              )
              .focusNode!;
    focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
  } else {
    await t.tap(find.descendant(of: tile, matching: find.byType(Text)));
  }
  await t.pump();
  await t.pump();
}

Future<void> capture(WidgetTester t, GlobalKey frame, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3Q'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final folder = Directory('build/reviews/interaction-batch3q');
      await folder.create(recursive: true);
      await File('${folder.path}/$name.png')
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
      testWidgets(
        '$suite $source chat selection cancels or applies only explicit draft',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final frame = GlobalKey();
            final (_, _, state) = await mount(t, suite, frame: frame);
            final entry = find.byKey(const Key('overlay-chat-select-sources'));
            await activate(t, entry, source);
            expect(
              route(t).animation!.value,
              source == 'pointer' ? lessThan(1) : 1,
            );
            await t.pumpAndSettle();
            final tiles = find.byType(StarBridgeCheckboxTile);
            await check(t, suite, tiles.first, source);
            final room = t.getSemantics(find.bySemanticsLabel('当前房间'));
            expect(
              room.getSemanticsData().flagsCollection.isChecked,
              CheckedState.isTrue,
            );
            expect(room.rect.width, greaterThan(350));
            expect(state.updates, 0);
            await activate(t, dialogAction('取消'), source);
            await t.pumpAndSettle();
            expect(state.value.chatSources, isEmpty);
            await activate(t, entry, source);
            await t.pumpAndSettle();
            await check(t, suite, tiles.first, source);
            await check(t, suite, tiles.at(1), source);
            await t.pumpAndSettle();
            if (source == 'pointer') {
              await capture(t, frame, '${suite.name}-chat');
            }
            await activate(t, dialogAction('应用选择'), source);
            if (source != 'pointer') {
              expect(find.byType(AlertDialog), findsNothing);
            }
            await t.pumpAndSettle();
            expect(state.updates, 1);
            expect(state.value.chatSources, [
              const OverlaySourceBinding.room(),
              OverlaySourceBinding.community('org-0', 'fixture-owner'),
            ]);
            await activate(
              t,
              find.widgetWithText(StarBridgeActionButton, '使用单一来源'),
              source,
            );
            await t.pumpAndSettle();
            expect(state.value.chatSources, isEmpty);
            expect(state.updates, 2);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite eight-source limit, unavailable selection and live reduce retain identity',
      (t) async {
        final (port, scenes, state) = await mount(t, suite);
        await activate(
          t,
          find.byKey(const Key('overlay-chat-select-sources')),
          'keyboard',
        );
        for (var i = 0; i < 8; i++) {
          await check(
            t,
            suite,
            find.byType(StarBridgeCheckboxTile).at(i),
            'pointer',
          );
        }
        await t.pumpAndSettle();
        expect(
          t
              .widget<StarBridgeCheckboxTile>(
                find.byType(StarBridgeCheckboxTile).last,
              )
              .onChanged,
          isNull,
        );
        port.state = directory(
          targets: const [OverlaySceneTarget('org-7', '剩余组织')],
        );
        await scenes.refresh();
        await t.pumpAndSettle();
        final missing = find.widgetWithText(StarBridgeCheckboxTile, '所选组织暂不可用');
        expect(missing, findsNWidgets(7));
        expect(
          t.widget<StarBridgeCheckboxTile>(missing.first).onChanged,
          isNotNull,
        );
        await check(t, suite, missing.first, 'keyboard');
        await t.pump();
        await t.pump();
        state.change(() => state.reduce = true);
        await t.pump();
        await t.pump();
        expect(route(t).animation!.value, 1);
        await activate(t, dialogAction('应用选择'), 'keyboard');
        expect(state.value.chatSources, hasLength(7));
        expect(state.updates, 1);
        expect(t.takeException(), isNull);
      },
    );

    for (final changeOwner in [false, true]) {
      testWidgets(
        '$suite account invalidation disables application owner=$changeOwner',
        (t) async {
          final (port, scenes, state) = await mount(t, suite);
          state.change(
            () => state.value = OverlayPresetSources(
              chatSources: [const OverlaySourceBinding.room()],
            ),
          );
          await t.pump();
          await activate(
            t,
            find.byKey(const Key('overlay-chat-select-sources')),
            'pointer',
          );
          await t.pump(const Duration(milliseconds: 50));
          port.state = directory(
            owner: changeOwner ? 'other-owner' : 'fixture-owner',
            generation: changeOwner ? 1 : 2,
          );
          await scenes.refresh();
          await t.pumpAndSettle();
          expect(find.byType(StarBridgeCheckboxTile), findsNothing);
          expect(
            t.widget<StarBridgeActionButton>(dialogAction('应用选择')).onActivate,
            isNull,
          );
          expect(state.updates, 0);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(find.byType(AlertDialog), findsNothing);
          expect(state.value.chatSources, [const OverlaySourceBinding.room()]);
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$suite source-limit nested chat edits save, keep undo and the Host warning',
      (t) async {
        final port = Port();
        final module = OverlayWorkspaceModule(port);
        addTearDown(module.dispose);
        await module.refresh();
        final frame = GlobalKey();
        final (_, _, state) = await mount(
          t,
          suite,
          module: module,
          frame: frame,
        );
        await activate(
          t,
          find.byKey(const Key('overlay-source-adjust')),
          'keyboard',
        );
        expect(route(t).animation!.value, 1);
        await t.pumpAndSettle();
        await activate(
          t,
          find.byKey(const Key('overlay-chat-select-sources')),
          'keyboard',
        );
        expect(find.byType(AlertDialog), findsNWidgets(2));
        await check(
          t,
          suite,
          find.byType(StarBridgeCheckboxTile).first,
          'keyboard',
        );
        await activate(t, dialogAction('应用选择'), 'keyboard');
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(module.projection.value.sources!.chatSources, [
          const OverlaySourceBinding.room(),
        ]);
        expect(module.projection.value.dirty, false);
        expect(port.writes.single.sources!.chatSources, [
          const OverlaySourceBinding.room(),
        ]);
        await capture(t, frame, '${suite.name}-limit');
        state.change(() => state.reduce = true);
        await t.pump();
        await t.pump();
        await activate(t, dialogAction('返回编辑器'), 'keyboard');
        await t.pumpAndSettle();
        expect(find.byKey(const Key('overlay-source-limit')), findsOneWidget);
        module.undo();
        expect(module.projection.value.sources!.chatSources, isEmpty);
        await t.pumpAndSettle();
        expect(port.writes.last.sources!.chatSources, isEmpty);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite checkbox row pointer feedback is interrupted by reader without value change',
      (t) async {
        size(t, const Size(800, 300));
        final semantics = t.ensureSemantics();
        var value = false, accept = true, reduce = false, enabled = true;
        int calls = 0;
        late StateSetter update;
        final frame = GlobalKey();
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (context, set) {
                update = set;
                return scopedApp(
                  Center(
                    child: RepaintBoundary(
                      key: frame,
                      child: SizedBox(
                        width: 420,
                        child: StarBridgeCheckboxTile(
                          value: value,
                          label: '条目',
                          onChanged: !enabled
                              ? null
                              : (next) {
                                  calls++;
                                  if (accept) set(() => value = next);
                                },
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
          final tile = find.byType(StarBridgeCheckboxTile);
          await check(t, suite, tile, 'pointer');
          await t.pump(const Duration(milliseconds: 35));
          final during = await pixels(t, frame);
          if (suite != InteractionSuite.standard) {
            expect(t.binding.hasScheduledFrame, true);
          }
          accept = false;
          await check(t, suite, tile, 'reader');
          expect(value, true);
          expect(calls, 2);
          expect(t.binding.hasScheduledFrame, false);
          if (suite != InteractionSuite.standard) {
            expect(await pixels(t, frame), isNot(during));
          }
          accept = true;
          await check(t, suite, tile, 'pointer');
          await check(t, suite, tile, 'pointer');
          update(() => reduce = true);
          await t.pump();
          await t.pump();
          expect(t.binding.hasScheduledFrame, false);
          update(() => enabled = false);
          await t.pumpAndSettle();
          final node = t.getSemantics(find.bySemanticsLabel('条目'));
          expect(node.getSemanticsData().hasAction(SemanticsAction.tap), false);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pump();
          expect(calls, 4);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
    testWidgets(
      '$suite programmatic checkbox updates do not reuse an old pointer origin',
      (t) async {
        size(t, const Size(800, 300));
        var value = false;
        var calls = 0;
        late StateSetter update;
        await t.pumpWidget(
          scopedApp(
            Center(
              child: SizedBox(
                width: 420,
                child: StatefulBuilder(
                  builder: (context, set) {
                    update = set;
                    return StarBridgeCheckboxTile(
                      value: value,
                      label: '条目',
                      onChanged: (next) => set(() {
                        calls++;
                        value = next;
                      }),
                    );
                  },
                ),
              ),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await check(t, suite, find.byType(StarBridgeCheckboxTile), 'pointer');
        await t.pumpAndSettle();
        update(() => value = false);
        await t.pumpAndSettle();
        update(() => value = true);
        await t.pump();
        await t.pump();
        if (suite != InteractionSuite.standard) {
          expect(t.binding.hasScheduledFrame, false);
        }
        expect(calls, 1);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite 200 percent text and leaving before apply cannot resurrect draft',
      (t) async {
        final (_, _, state) = await mount(t, suite);
        t.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpAndSettle();
        await activate(
          t,
          find.byKey(const Key('overlay-chat-select-sources')),
          'keyboard',
        );
        await t.pumpAndSettle();
        await check(
          t,
          suite,
          find.byType(StarBridgeCheckboxTile).first,
          'keyboard',
        );
        state.change(() => state.show = false);
        await t.pump();
        await t.pump();
        await activate(t, dialogAction('应用选择'), 'keyboard');
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('已离开'), findsOneWidget);
        expect(state.value.chatSources, isEmpty);
        expect(state.updates, 0);
        expect(t.takeException(), isNull);
      },
    );
  }
}
