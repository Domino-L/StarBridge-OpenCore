import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_overlay_settings.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/platform/window/menu_preview_window_port.dart';

import 'interaction_batch3ca_test.dart' show MenuPort, fire;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3b_test.dart' show exposedNodes;
import '../../features/friends/social_layout_test.dart' show size;

class LivePort implements MenuLiveWindowPort {
  @override
  bool liveAvailable = true;
  int demos = 0, disposals = 0;
  final calls = <(InteractionSource, String, String, String)>[];
  final pending = <Completer<bool>>[];
  @override
  Future<bool> openLive({
    required String contextLabel,
    required String returnLabel,
    required String settingsLabel,
  }) {
    calls.add((
      currentStarBridgeActivationSource,
      contextLabel,
      returnLabel,
      settingsLabel,
    ));
    final next = Completer<bool>();
    pending.add(next);
    return next.future;
  }

  @override
  Future<bool> open({
    required String contextLabel,
    required String returnLabel,
    required String settingsLabel,
  }) async {
    demos++;
    return false;
  }

  @override
  void dispose() {
    disposals++;
  }

  void finish([bool result = true]) {
    for (final c in pending) {
      if (!c.isCompleted) c.complete(result);
    }
  }
}

class Harness extends StatefulWidget {
  const Harness(this.port, this.suite, {super.key, this.local = false});
  final LivePort port;
  final InteractionSuite suite;
  final bool local;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late LivePort port = widget.port;
  late InteractionSuite suite = widget.suite;
  bool reduce = false,
      light = false,
      visible = true,
      selected = false,
      enabled = true;
  int actions = 0;
  MenuSettingsDraft? draft;
  final sources = <InteractionSource>[];
  final tools = MenuLocalToolsController(
    (_, _) async => throw StateError('No native action permitted'),
  );
  late final workspace = MenuWorkspaceController(
    scope: Object(),
    panels: [
      MenuPanelSpec(
        id: 'one',
        initialBounds: const Rect.fromLTWH(40, 50, 260, 180),
      ),
      MenuPanelSpec(
        id: 'two',
        initialBounds: const Rect.fromLTWH(360, 240, 260, 180),
      ),
    ],
  );
  final geometrySources = <InteractionSource>[],
      settingsSources = <InteractionSource>[];
  @override
  void initState() {
    super.initState();
    workspace.open('one');
    workspace.open('two');
    tools.addListener(
      () => settingsSources.add(currentStarBridgeActivationSource),
    );
    workspace.addListener(
      () => geometrySources.add(currentStarBridgeActivationSource),
    );
  }

  void change(VoidCallback action) => setState(action);
  @override
  void dispose() {
    tools.dispose();
    workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => scopedApp(
    visible
        ? widget.local
              ? MenuLocalSettings(tools: tools, workspace: workspace)
              : MenuOverlaySettings(preview: port, draft: draft)
        : const SizedBox(),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<HarnessState> mount(
  WidgetTester t,
  LivePort port,
  InteractionSuite suite, {
  bool local = false,
}) async {
  size(t, const Size(1100, 1000));
  final k = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(port, suite, key: k, local: local));
  await frames(t);
  return k.currentState!;
}

Future<void> close(WidgetTester t, Iterable<LivePort> ports) async {
  for (final p in ports) {
    p.finish();
  }
  await frames(t);
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

InteractionSource origin(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;
Finder get open => find.byKey(const Key('menu-overlay-open-live'));
Future<void> activate(WidgetTester t, String input, String id) =>
    fire(t, input, find.byKey(Key(id)));
void waiting(WidgetTester t, bool reduce) {
  expect(find.byType(SuiteBusyLabel), findsOneWidget);
  expect(
    InteractionScope.of(t.element(find.byType(SuiteBusyLabel))).reduceMotion,
    reduce,
  );
}

Future<void> slide(
  WidgetTester t,
  String input, {
  LogicalKeyboardKey key = LogicalKeyboardKey.arrowRight,
}) async {
  final adapter = find.ancestor(
    of: find.byKey(const Key('menu-local-dimming')),
    matching: find.byType(StarBridgeSlider),
  );
  await t.ensureVisible(adapter);
  final native = find.descendant(of: adapter, matching: find.byType(Slider));
  final fx = find.descendant(of: adapter, matching: find.byType(SuiteSlider));
  if (input == 'reader') {
    final label = t.widget<StarBridgeSlider>(adapter).semanticLabel;
    final node = exposedNodes(t).singleWhere(
      (node) =>
          node.getSemanticsData().flagsCollection.isSlider &&
          node.getSemanticsData().label == label,
    );
    expect(
      node.getSemanticsData().hasAction(ui.SemanticsAction.increase),
      isTrue,
    );
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.increase,
    );
  } else if (input == 'keyboard') {
    final focus = native.evaluate().isNotEmpty
        ? t.widget<Slider>(native).focusNode
        : t.widget<SuiteSlider>(fx).focusNode;
    focus!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(key);
  } else {
    await t.drag(
      native.evaluate().isNotEmpty ? native : fx,
      const Offset(100, 0),
    );
  }
  await t.pump();
  await t.pump();
}

class ActionHarness extends StatefulWidget {
  const ActionHarness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<ActionHarness> createState() => ActionState();
}

class ActionState extends State<ActionHarness> {
  late var suite = widget.suite;
  bool enabled = true, selected = false, reduce = false, light = false;
  final sources = <InteractionSource>[];
  bool throwNext = false;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    Center(
      child: BridgeMenuAction(
        key: const Key('shared'),
        label: 'Shared action',
        selected: selected,
        onPressed: enabled
            ? () {
                sources.add(currentStarBridgeActivationSource);
                if (throwNext) throw StateError('Synchronous fixture');
              }
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: const Text('Shared action'),
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<ActionState> actionMount(WidgetTester t, InteractionSuite suite) async {
  final k = GlobalKey<ActionState>();
  await t.pumpWidget(ActionHarness(suite, key: k));
  await frames(t);
  return k.currentState!;
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final result in ['success', 'false', 'error']) {
        testWidgets(
          '$suite $input live open $result actual result and no duplicate',
          (t) async {
            final semantics = t.ensureSemantics();
            final port = LivePort();
            try {
              await mount(t, port, suite);
              await activate(t, input, 'menu-overlay-open-live');
              await t.pump();
              waiting(t, input != 'pointer');
              expect(port.calls.single.$1, origin(input));
              expect(port.calls.single.$2, '菜单浮层');
              expect(port.calls.single.$4, '菜单浮层');
              expect(port.calls.single.$3, isNotEmpty);
              final button = t.widget<StarBridgeActionButton>(
                find.ancestor(
                  of: open,
                  matching: find.byType(StarBridgeActionButton),
                ),
              );
              expect(button.onActivate, isNull);
              expect(
                find.byKey(const Key('menu-overlay-open-failed')),
                findsNothing,
              );
              if (result == 'error') {
                port.pending.single.completeError(
                  StateError('Synthetic open failure'),
                );
              } else {
                port.pending.single.complete(result == 'success');
              }
              await frames(t);
              expect(find.byType(SuiteBusyLabel), findsNothing);
              expect(
                find.byKey(const Key('menu-overlay-open-failed')),
                result == 'success' ? findsNothing : findsOneWidget,
              );
              expect(port.calls, hasLength(1));
              expect(port.demos, 0);
              expect(port.disposals, 0);
              if (result != 'success') {
                await activate(t, input, 'menu-overlay-open-live');
                await frames(t);
                expect(port.calls, hasLength(2));
                port.pending.last.complete(true);
                await frames(t);
                expect(
                  find.byKey(const Key('menu-overlay-open-failed')),
                  findsNothing,
                );
              }
            } finally {
              semantics.dispose();
              await close(t, [port]);
            }
          },
        );
      }
      testWidgets(
        '$suite $input shared action exactly once, static keyboard and semantic selected',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final h = await actionMount(t, suite);
            await activate(t, input, 'shared');
            await frames(t);
            expect(h.sources, [origin(input)]);
            h.change(() => h.selected = true);
            await frames(t);
            final node = t.getSemantics(find.byKey(const Key('shared')));
            expect(
              node.getSemanticsData().flagsCollection.isSelected,
              ui.Tristate.isTrue,
            );
            if (suite != InteractionSuite.standard) {
              final control = t.widget<SuitePressable>(
                find.byType(SuitePressable),
              );
              expect(control.selected, true);
            }
            h.change(() => h.enabled = false);
            await frames(t);
            final disabled = t.getSemantics(find.byKey(const Key('shared')));
            expect(
              disabled.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              false,
            );
            await t.tap(find.byKey(const Key('shared')), warnIfMissed: false);
            await frames(t);
            expect(h.sources, hasLength(1));
          } finally {
            semantics.dispose();
            await t.pumpWidget(const SizedBox());
          }
        },
      );
      testWidgets(
        '$suite $input actual local snap/reset/slider retain original immediate owners',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = LivePort();
          try {
            final h = await mount(t, port, suite, local: true);
            await activate(t, input, 'menu-local-snap');
            await frames(t);
            expect(h.tools.snapWindows, true);
            expect(h.settingsSources.single, origin(input));
            expect(
              t
                  .widget<BridgeMenuAction>(
                    find.byKey(const Key('menu-local-snap')),
                  )
                  .selected,
              true,
            );
            final lease = h.workspace.openPanels.first;
            h.workspace.moveTo(
              lease,
              const Offset(220, 310),
              const Size(1100, 1000),
              snap: false,
            );
            expect(
              h.workspace.boundsFor('one', const Size(1100, 1000)).topLeft,
              const Offset(220, 310),
            );
            h.geometrySources.clear();
            await activate(t, input, 'menu-local-reset-layout');
            await frames(t);
            expect(h.geometrySources, [origin(input)]);
            expect(
              h.workspace.boundsFor('one', const Size(1100, 1000)).topLeft,
              const Offset(40, 50),
            );
            final before = h.tools.dimming;
            h.settingsSources.clear();
            await slide(t, input);
            await frames(t);
            expect(h.tools.dimming, greaterThan(before));
            expect(h.settingsSources, isNotEmpty);
            expect(h.settingsSources.every((s) => s == origin(input)), true);
            expect(port.calls, isEmpty);
            expect(port.demos, 0);
          } finally {
            semantics.dispose();
            await close(t, [port]);
          }
        },
      );
    }
    for (final result in ['success', 'false', 'error']) {
      testWidgets(
        '$suite old live reply $result cannot settle replacement pointer open',
        (t) async {
          final a = LivePort(), b = LivePort();
          try {
            final h = await mount(t, a, suite);
            await activate(t, 'keyboard', 'menu-overlay-open-live');
            await frames(t);
            h.change(() => h.port = b);
            await frames(t);
            await activate(t, 'pointer', 'menu-overlay-open-live');
            await frames(t);
            waiting(t, false);
            if (result == 'error') {
              a.pending.single.completeError(StateError('Synthetic old error'));
            } else {
              a.pending.single.complete(result == 'success');
            }
            await frames(t);
            waiting(t, false);
            expect(
              find.byKey(const Key('menu-overlay-open-failed')),
              findsNothing,
            );
            expect(b.calls, hasLength(1));
            b.pending.single.complete(true);
            await frames(t);
            expect(find.byType(SuiteBusyLabel), findsNothing);
            expect(a.disposals, 0);
            expect(b.disposals, 0);
          } finally {
            await close(t, [a, b]);
          }
        },
      );
      testWidgets('$suite removed live entry ignores late $result', (t) async {
        final port = LivePort();
        try {
          final h = await mount(t, port, suite);
          await activate(t, 'pointer', 'menu-overlay-open-live');
          await frames(t);
          h.change(() => h.visible = false);
          await t.pump();
          if (result == 'error') {
            port.pending.single.completeError(
              StateError('Synthetic removed error'),
            );
          } else {
            port.pending.single.complete(result == 'success');
          }
          await frames(t);
          expect(t.takeException(), isNull);
          expect(port.disposals, 0);
        } finally {
          await close(t, [port]);
        }
      });
    }
    testWidgets(
      '$suite same native port, replaced page draft invalidates UI reply',
      (t) async {
        final port = LivePort(),
            d1 = MenuSettingsDraft(MenuPort()),
            d2 = MenuSettingsDraft(MenuPort());
        try {
          await d1.initialize();
          await d2.initialize();
          final h = await mount(t, port, suite);
          h.change(() => h.draft = d1);
          await frames(t);
          await activate(t, 'pointer', 'menu-overlay-open-live');
          await frames(t);
          h.change(() => h.draft = d2);
          await frames(t);
          await activate(t, 'pointer', 'menu-overlay-open-live');
          await frames(t);
          expect(port.calls, hasLength(2));
          port.pending.first.complete(false);
          await frames(t);
          waiting(t, false);
          expect(
            find.byKey(const Key('menu-overlay-open-failed')),
            findsNothing,
          );
        } finally {
          await close(t, [port]);
          d1.dispose();
          d2.dispose();
        }
      },
    );
    testWidgets('$suite unavailable never dispatches native open', (t) async {
      final port = LivePort()..liveAvailable = false;
      try {
        await mount(t, port, suite);
        final action = t.widget<StarBridgeActionButton>(
          find.ancestor(
            of: open,
            matching: find.byType(StarBridgeActionButton),
          ),
        );
        expect(action.onActivate, isNull);
        expect(port.calls, isEmpty);
        expect(port.demos, 0);
      } finally {
        await close(t, [port]);
      }
    });
    testWidgets(
      '$suite shared press feedback retained through rapid active clicks',
      (t) async {
        final h = await actionMount(t, suite);
        for (var i = 0; i < 6; i++) {
          await t.tap(find.byKey(const Key('shared')));
          await t.pump(const Duration(milliseconds: 40));
        }
        expect(h.sources, List.filled(6, InteractionSource.pointer));
        if (suite != InteractionSuite.standard) {
          expect(find.byType(SuitePressable), findsOneWidget);
        }
        await frames(t);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('$suite Enter Space and numpad Enter activate once each', (
      t,
    ) async {
      final h = await actionMount(t, suite);
      await activate(t, 'keyboard', 'shared');
      await frames(t);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await t.pump();
      expect(h.sources, List.filled(3, InteractionSource.keyboard));
      h.change(() => h.enabled = false);
      await frames(t);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      expect(h.sources, hasLength(3));
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$suite shared callback exceptions remain framework-visible', (
      t,
    ) async {
      final h = await actionMount(t, suite);
      h.change(() => h.throwNext = true);
      await frames(t);
      await t.tap(find.byKey(const Key('shared')));
      expect(t.takeException(), isA<StateError>());
      expect(h.sources, [InteractionSource.pointer]);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$suite shared focus/geometry survives suite and live reduction changes',
      (t) async {
        final h = await actionMount(t, suite);
        final original = t.getSize(find.byKey(const Key('shared')));
        await activate(t, 'keyboard', 'shared');
        await frames(t);
        h.change(() {
          h.reduce = true;
          h.light = true;
        });
        await t.pump();
        await t.pump();
        expect(
          Theme.of(t.element(find.text('Shared action'))).brightness,
          Brightness.light,
        );
        for (final next in InteractionSuite.values) {
          h.change(() => h.suite = next);
          await frames(t);
          expect(t.getSize(find.byKey(const Key('shared'))), original);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pump();
        }
        expect(h.sources, List.filled(5, InteractionSource.keyboard));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite open wait follows live reduction and theme within two frames',
      (t) async {
        final port = LivePort();
        try {
          final h = await mount(t, port, suite);
          await activate(t, 'pointer', 'menu-overlay-open-live');
          await t.pump();
          waiting(t, false);
          h.change(() {
            h.reduce = true;
            h.light = true;
          });
          await t.pump();
          await t.pump();
          waiting(t, true);
          expect(
            Theme.of(t.element(find.byType(SuiteBusyLabel))).brightness,
            Brightness.light,
          );
          h.change(() => h.reduce = false);
          await t.pump();
          await t.pump();
          waiting(t, false);
        } finally {
          await close(t, [port]);
        }
      },
    );
  }
}
