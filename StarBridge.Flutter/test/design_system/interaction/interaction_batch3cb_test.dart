import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_save_bar.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_geometry_fields.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_save_bar_visibility.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';

import 'interaction_batch3bz_test.dart' show FullFixture;
import 'interaction_batch3ca_test.dart'
    show MenuFixture, MenuHarness, key, view;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;

class VisibilityOwner extends ChangeNotifier {
  bool get subscribed => hasListeners;
  bool visible = false;
  String title = 'draft';
  int taps = 0;
  Completer<void>? pending;
  Future<void> save() async {
    taps++;
    await pending?.future;
  }

  void change(bool value, {String? text}) {
    visible = value;
    title = text ?? title;
    notifyListeners();
  }
}

class VisibilityHarness extends StatefulWidget {
  const VisibilityHarness(this.owner, this.suite, {super.key});
  final VisibilityOwner owner;
  final InteractionSuite suite;
  @override
  State<VisibilityHarness> createState() => VisibilityHarnessState();
}

class VisibilityHarnessState extends State<VisibilityHarness> {
  late var owner = widget.owner;
  bool reduce = false,
      visiblePage = true,
      systemReduce = false,
      saveBar = false;
  late var suite = widget.suite;
  final focus = FocusNode();
  void change(VoidCallback action) => setState(action);
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => scopedApp(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: systemReduce),
        child: visiblePage
            ? Align(
                alignment: Alignment.bottomCenter,
                child: OverlaySettingsSaveBarVisibility(
                  owner: owner,
                  isVisible: () => owner.visible,
                  builder: (_) => saveBar
                      ? OverlaySettingsSaveBar(
                          busy: false,
                          onUndo: null,
                          onRedo: null,
                          onDiscard: null,
                          onSave: owner.save,
                          saveKey: const Key('surface-save'),
                        )
                      : SizedBox(
                          width: 500,
                          height: 80,
                          child: StarBridgeActionButton(
                            controlKey: const Key('surface-action'),
                            focusNode: focus,
                            onActivate: (_) => owner.taps++,
                            child: Text(owner.title),
                          ),
                        ),
                ),
              )
            : const SizedBox(),
      ),
    ),
    suite,
    reduce: reduce,
  );
}

Animation<double> animation(WidgetTester t) => t
    .widget<SuiteSurfaceTransition>(find.byType(SuiteSurfaceTransition).first)
    .animation;

Future<VisibilityHarnessState> mount(
  WidgetTester t,
  VisibilityOwner owner,
  InteractionSuite suite,
) async {
  await view(t);
  final key = GlobalKey<VisibilityHarnessState>();
  await t.pumpWidget(VisibilityHarness(owner, suite, key: key));
  await t.pump();
  await t.pump();
  expect(owner.subscribed, isTrue);
  return key.currentState!;
}

void command(
  VisibilityOwner owner,
  bool shown,
  InteractionSource source, {
  String? text,
}) => runStarBridgeSynchronousActivation(
  source,
  () => owner.change(shown, text: text),
);

bool containsLabel(SemanticsNode root, String label) {
  if (root.getSemanticsData().label == label) return true;
  var found = false;
  root.visitChildren((child) {
    found = found || containsLabel(child, label);
    return true;
  });
  return found;
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite menu clean undo keeps the original redo-only bar', (
      t,
    ) async {
      final h = MenuFixture();
      try {
        await view(t);
        await h.load();
        h.draft.discard();
        h.draft.change({'showClock': false});
        await t.pumpWidget(MenuHarness(h, suite));
        await frames(t);
        await key(t, 'keyboard', 'overlay-save-bar-undo');
        expect(h.draft.dirty, isFalse);
        expect(h.draft.canRedo, isTrue);
        final bar = t.widget<OverlaySettingsSaveBar>(
          find.byType(OverlaySettingsSaveBar),
        );
        expect(bar.dirty, isFalse);
        expect(bar.onSave, isNull);
        expect(bar.onRedo, isNotNull);
        await key(t, 'pointer', 'overlay-save-bar-redo');
        expect(h.draft.dirty, isTrue);
        expect(h.port.sources, isEmpty);
      } finally {
        await h.clean(t);
      }
    });
    for (final reject in [false, true]) {
      testWidgets(
        '$suite actual page leave and return after save reject=$reject',
        (t) async {
          final h = FullFixture();
          try {
            await view(t);
            await h.module.initialize();
            await t.pumpWidget(
              scopedApp(OverlayWorkspacePage(module: h.module), suite),
            );
            await frames(t);
            h.port.pending = Completer<void>();
            h.port.reject = reject;
            h.module.updateSetting('showMembers', true);
            await frames(t);
            expect(h.port.writes, hasLength(1));
            await t.pumpWidget(const SizedBox());
            h.port.pending!.complete();
            await t.pump();
            await t.pump();
            expect(h.module.projection.value.dirty, reject);
            await t.pumpWidget(
              scopedApp(OverlayWorkspacePage(module: h.module), suite),
            );
            await frames(t);
            expect(find.byType(OverlaySettingsSaveBar), findsNothing);
            expect(
              find.byKey(const Key('overlay-workspace-retry-failure')),
              reject ? findsOneWidget : findsNothing,
            );
            // A conflict re-reads once and retries before it reports.
            expect(h.port.writes, hasLength(reject ? 2 : 1));
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
          }
        },
      );
    }
    testWidgets('$suite one surface reverses without losing the new content', (
      t,
    ) async {
      final owner = VisibilityOwner();
      await mount(t, owner, suite);
      command(owner, true, InteractionSource.pointer);
      await t.pump();
      await t.pump(const Duration(milliseconds: 70));
      final a = animation(t);
      expect(a.value, inExclusiveRange(0, 1));
      command(owner, false, InteractionSource.pointer, text: 'clean');
      await t.pump();
      expect(a.status, AnimationStatus.reverse);
      expect(find.text('draft'), findsOneWidget);
      expect(find.text('clean'), findsNothing);
      await t.pump(const Duration(milliseconds: 15));
      final retiring = a.value;
      command(owner, true, InteractionSource.pointer, text: 'new draft');
      await t.pump();
      expect(animation(t), same(a));
      expect(a.value, closeTo(retiring, .00001));
      expect(find.byKey(const Key('surface-action')), findsOneWidget);
      expect(find.text('new draft'), findsOneWidget);
      await frames(t);
      expect(a.status, AnimationStatus.completed);
      expect(find.text('new draft'), findsOneWidget);
      await key(t, 'pointer', 'surface-action');
      expect(owner.taps, 1);
      await t.pumpWidget(const SizedBox());
      owner.dispose();
    });
    testWidgets(
      '$suite retiring surface cannot receive focus hit or semantics',
      (t) async {
        final owner = VisibilityOwner();
        final state = await mount(t, owner, suite);
        final semantics = t.ensureSemantics();
        try {
          command(owner, true, InteractionSource.pointer);
          await frames(t);
          state.focus.requestFocus();
          await t.pump();
          expect(state.focus.hasFocus, isTrue);
          final point = t.getCenter(find.byKey(const Key('surface-action')));
          command(owner, false, InteractionSource.pointer);
          await t.pump();
          await t.pump();
          expect(state.focus.hasFocus, isFalse);
          state.focus.requestFocus();
          await t.pump();
          expect(state.focus.hasFocus, isFalse);
          expect(
            containsLabel(
              t
                  .binding
                  .renderViews
                  .single
                  .owner!
                  .semanticsOwner!
                  .rootSemanticsNode!,
              'draft',
            ),
            isFalse,
          );
          await t.tapAt(point);
          await t.pump();
          expect(owner.taps, 0);
          await frames(t);
          expect(find.byKey(const Key('surface-action')), findsNothing);
        } finally {
          semantics.dispose();
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
    for (final system in [false, true]) {
      for (final entering in [false, true]) {
        testWidgets(
          '$suite live reduce system=$system entering=$entering settles controller',
          (t) async {
            final owner = VisibilityOwner();
            final state = await mount(t, owner, suite);
            command(owner, true, InteractionSource.pointer);
            await t.pump();
            await t.pump(const Duration(milliseconds: 40));
            if (!entering) {
              await frames(t);
              command(owner, false, InteractionSource.pointer);
              await t.pump();
              await t.pump(const Duration(milliseconds: 20));
            }
            final a = animation(t);
            state.change(() {
              if (system) {
                state.systemReduce = true;
              } else {
                state.reduce = true;
              }
            });
            await t.pump();
            await t.pump();
            expect(a.value, entering ? 1 : 0);
            expect(
              a.status,
              entering ? AnimationStatus.completed : AnimationStatus.dismissed,
            );
            expect(
              find.byKey(const Key('surface-action')),
              entering ? findsOneWidget : findsNothing,
            );
            await t.pumpWidget(const SizedBox());
            owner.dispose();
          },
        );
      }
    }
    testWidgets('$suite keyboard entry does not mute later pointer controls', (
      t,
    ) async {
      final owner = VisibilityOwner();
      await mount(t, owner, suite);
      command(owner, true, InteractionSource.keyboard);
      await t.pump();
      expect(animation(t).value, 1);
      final button = t.element(find.text('draft'));
      expect(InteractionScope.of(button).reduceMotion, isFalse);
      await key(t, 'pointer', 'surface-action');
      expect(owner.taps, 1);
      command(owner, false, InteractionSource.keyboard);
      await t.pump();
      expect(find.byKey(const Key('surface-action')), findsNothing);
      await t.pumpWidget(const SizedBox());
      owner.dispose();
    });
    testWidgets('$suite replaced owner drops stale exit and unsubscribes', (
      t,
    ) async {
      final first = VisibilityOwner(), second = VisibilityOwner();
      final state = await mount(t, first, suite);
      command(first, true, InteractionSource.pointer);
      await frames(t);
      command(first, false, InteractionSource.pointer);
      await t.pump();
      second.change(true, text: 'second owner');
      state.change(() => state.owner = second);
      await t.pump();
      first.change(true, text: 'stale owner');
      await frames(t);
      expect(find.text('second owner'), findsOneWidget);
      expect(find.text('stale owner'), findsNothing);
      expect(first.subscribed, isFalse);
      state.change(() => state.visiblePage = false);
      await t.pump();
      expect(second.subscribed, isFalse);
      second.change(false);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      first.dispose();
      second.dispose();
    });
    testWidgets('$suite owner replacement isolates pending save state', (
      t,
    ) async {
      final first = VisibilityOwner()
        ..change(true)
        ..pending = Completer<void>();
      final second = VisibilityOwner()
        ..change(true)
        ..pending = Completer<void>();
      final state = await mount(t, first, suite);
      state.change(() => state.saveBar = true);
      await frames(t);
      await key(t, 'pointer', 'surface-save');
      expect(first.taps, 1);
      state.change(() => state.owner = second);
      await frames(t);
      await key(t, 'pointer', 'surface-save');
      expect(second.taps, 1);
      first.pending!.complete();
      await t.pump();
      await t.pump();
      // A's late completion cannot unlock B while B's own save is pending.
      await key(t, 'pointer', 'surface-save');
      expect(second.taps, 1);
      second.pending!.complete();
      await frames(t);
      await key(t, 'pointer', 'surface-save');
      expect(second.taps, 2);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
      first.dispose();
      second.dispose();
    });
    for (final inputAction in ['done', 'tab', 'pointer-blur']) {
      testWidgets(
        '$suite actual native pixel $inputAction retains input source',
        (t) async {
          final h = FullFixture();
          try {
            await view(t);
            await h.module.initialize();
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder(
                  valueListenable: h.module.projection,
                  builder: (context, p, _) => Column(
                    children: [
                      OverlayWorkspaceGeometryFields(
                        item: p.layout.first,
                        enabled: true,
                        onChanged: (v) =>
                            h.module.updateLayoutItem(v, coalesce: false),
                      ),
                      OverlaySettingsSaveBarVisibility(
                        owner: h.module.projection,
                        isVisible: () => h.module.projection.value.dirty,
                        builder: (_) => const Text('native dirty'),
                      ),
                    ],
                  ),
                ),
                suite,
              ),
            );
            await frames(t);
            // Hold the save open so the edit stays visible while checking.
            h.port.pending = Completer<void>();
            final input = find.descendant(
              of: find.byKey(const Key('overlay-pixels-Notice-x')),
              matching: find.byType(TextField),
            );
            await t.enterText(input, '120');
            await t.pump();
            if (inputAction == 'done') {
              await t.testTextInput.receiveAction(TextInputAction.done);
            } else if (inputAction == 'tab') {
              await t.sendKeyEvent(LogicalKeyboardKey.tab);
            } else {
              await t.tapAt(const Offset(1200, 800));
            }
            await t.pump();
            await t.pump();
            expect(h.module.projection.value.dirty, isTrue);
            expect(animation(t).value, inputAction == 'pointer-blur' ? 0 : 1);
            expect(h.port.writes, hasLength(1));
          } finally {
            await h.clean(t);
          }
        },
      );
    }
    for (final input in ['keyboard', 'reader']) {
      testWidgets('$suite menu $input exit is immediate', (t) async {
        final h = MenuFixture();
        final semantics = t.ensureSemantics();
        try {
          await view(t);
          await h.load();
          await t.pumpWidget(MenuHarness(h, suite));
          await frames(t);
          await key(t, input, 'menu-workspace-discard');
          expect(h.draft.dirty, isFalse);
          expect(find.byType(OverlaySettingsSaveBar), findsNothing);
          expect(h.port.sources, isEmpty);
        } finally {
          semantics.dispose();
          await h.clean(t);
        }
      });
    }
    for (final reject in [false, true]) {
      testWidgets(
        '$suite information real save reply reject=$reject retains owner truth',
        (t) async {
          final h = FullFixture();
          try {
            await view(t);
            await h.module.initialize();
            await t.pumpWidget(
              scopedApp(OverlayWorkspacePage(module: h.module), suite),
            );
            await frames(t);
            h.port.pending = Completer<void>();
            h.port.reject = reject;
            h.module.updateSetting('showMembers', true);
            await frames(t);
            final status = find.byKey(const Key('overlay-preset-save-status'));
            expect(h.port.writes, hasLength(1));
            expect(h.module.projection.value.dirty, isTrue);
            expect(t.widget<Text>(status).data, '正在保存更改…');
            expect(find.byType(OverlaySettingsSaveBar), findsNothing);
            h.port.pending!.complete();
            await frames(t);
            expect(h.module.projection.value.dirty, reject);
            expect(t.widget<Text>(status).data, reject ? '未保存' : '已保存');
            expect(
              find.byKey(const Key('overlay-workspace-retry-failure')),
              reject ? findsOneWidget : findsNothing,
            );
            expect(find.byType(OverlaySettingsSaveBar), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
          }
        },
      );
    }
    testWidgets('$suite information keyboard undo shows no save bar', (
      t,
    ) async {
      final h = FullFixture();
      try {
        await view(t);
        await h.module.initialize();
        h.module.updateSetting('showMembers', true);
        await t.pumpWidget(
          scopedApp(OverlayWorkspacePage(module: h.module), suite),
        );
        await frames(t);
        await key(t, 'keyboard', 'overlay-preset-undo');
        await frames(t);
        expect(h.module.projection.value.settings!['showMembers'], isFalse);
        expect(h.module.projection.value.dirty, isFalse);
        expect(h.module.canRedo, isTrue);
        expect(find.byType(OverlaySettingsSaveBar), findsNothing);
        expect(h.port.writes, hasLength(2));
      } finally {
        await h.clean(t);
      }
    });
    testWidgets('$suite menu pointer exit retains the old draft surface', (
      t,
    ) async {
      final h = MenuFixture();
      try {
        await view(t);
        await h.load();
        await t.pumpWidget(MenuHarness(h, suite));
        await frames(t);
        await key(t, 'pointer', 'menu-workspace-discard');
        expect(h.draft.dirty, isFalse);
        expect(h.draft.canRedo, isFalse);
        final bar = find.byType(OverlaySettingsSaveBar);
        expect(bar, findsOneWidget);
        expect(t.widget<OverlaySettingsSaveBar>(bar).dirty, isTrue);
        final focus = find.ancestor(
          of: bar,
          matching: find.byType(ExcludeFocus),
        );
        expect(
          focus.evaluate().any((e) => (e.widget as ExcludeFocus).excluding),
          isTrue,
        );
        await frames(t);
        expect(bar, findsNothing);
        expect(h.port.sources, isEmpty);
      } finally {
        await h.clean(t);
      }
    });
    testWidgets(
      '$suite information page with reduced motion shows no save bar',
      (t) async {
        final h = FullFixture();
        try {
          await view(t);
          await h.module.initialize();
          h.module.updateSetting('showMembers', true);
          await t.pumpWidget(
            scopedApp(
              OverlayWorkspacePage(module: h.module),
              suite,
              reduce: true,
            ),
          );
          await frames(t);
          runStarBridgeSynchronousActivation(
            InteractionSource.pointer,
            h.module.undo,
          );
          await t.pump();
          await t.pump();
          expect(find.byType(OverlaySettingsSaveBar), findsNothing);
          expect(h.module.projection.value.settings!['showMembers'], isFalse);
          expect(h.port.writes, hasLength(2));
        } finally {
          await h.clean(t);
        }
      },
    );
  }
}
