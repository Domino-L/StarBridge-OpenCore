import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_workspace.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_page.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

import 'interaction_batch3x_test.dart' show readyPreferences;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ca_test.dart' show key, fire;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3bz_test.dart' show FullFixture;

class ReadPort implements MenuWindowPreferencesPort {
  var value = readyPreferences();
  int reads = 0, writes = 0;
  bool failRead = false, failSave = false;
  final sources = <InteractionSource>[];
  Completer<void>? pending;
  @override
  Future<MenuWindowPreferences> read() async {
    reads++;
    sources.add(currentStarBridgeActivationSource);
    await pending?.future;
    if (failRead) throw StateError('Synthetic unavailable');
    return value;
  }

  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences next) async {
    writes++;
    if (failSave) throw StateError('Synthetic rejected save');
    return value = MenuWindowPreferences(
      next.revision + 1,
      next.layout,
      next.settings,
    );
  }
}

class Fixture {
  final port = ReadPort();
  late final draft = MenuSettingsDraft(port);
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
  final Fixture fixture;
  final InteractionSuite suite;
  @override
  State<MenuHarness> createState() => MenuHarnessState();
}

class MenuHarnessState extends State<MenuHarness> {
  late var draft = widget.fixture.draft;
  late var suite = widget.suite;
  bool reduce = false, light = false, show = true;
  final input = TextEditingController();
  void change(VoidCallback action) => setState(action);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => scopedApp(
    show
        ? MenuSettingsWorkspace(
            draft: draft,
            shortcuts: TextField(
              key: const Key('independent-editor'),
              controller: input,
            ),
          )
        : const SizedBox(),
    suite,
    reduce: reduce,
    light: light,
  );
}

void viewport(WidgetTester t, double width) {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<MenuHarnessState> mount(
  WidgetTester t,
  Fixture h,
  InteractionSuite suite, {
  double width = 1100,
}) async {
  viewport(t, width);
  final k = GlobalKey<MenuHarnessState>();
  await t.pumpWidget(MenuHarness(h, suite, key: k));
  await frames(t);
  return k.currentState!;
}

Finder get menus => find.byWidgetPredicate(
  (w) => w is SuiteSurfaceTransition && w.kind == SurfaceKind.menu,
);
Future<void> choose(WidgetTester t, String input, String id) async {
  await key(t, input, 'menu-workspace-section-command');
  await frames(t);
  expect(menus, findsOneWidget);
  if (input != 'pointer') {
    expect(t.widget<SuiteSurfaceTransition>(menus).animation.value, 1);
  }
  await fire(
    t,
    input,
    find.byKey(ValueKey<Object>(('menu-workspace-section', id))),
  );
  await frames(t);
  expect(menus, findsNothing);
  expect(find.byKey(ValueKey('menu-section-$id')), findsOneWidget);
  final field = find.byKey(ValueKey('menu-section-$id'));
  expect(t.widget<StarBridgeSelectFormField<String>>(field).initialValue, id);
  expect(t.state<FormFieldState<String>>(field).value, id);
  expect(t.takeException(), isNull);
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite shared information toggle keeps saved geometry', (
      t,
    ) async {
      final h = FullFixture();
      final semantics = t.ensureSemantics();
      try {
        viewport(t, 430);
        await h.module.initialize();
        h.module.updateSetting('showMembers', true);
        final before = h.module.projection.value.layout;
        await t.pumpWidget(
          scopedApp(OverlayWorkspacePage(module: h.module), suite),
        );
        await frames(t);
        var shown = false;
        for (final input in ['pointer', 'keyboard', 'reader', 'pointer']) {
          await key(t, input, 'overlay-settings-expand');
          await frames(t);
          shown = !shown;
          expect(
            find.byKey(const Key('overlay-settings-dock')),
            shown ? findsOneWidget : findsNothing,
          );
          expect(h.module.projection.value.layout, before);
          // The edit saved once; toggling the dock writes nothing more.
          expect(h.module.projection.value.dirty, isFalse);
          expect(h.port.writes, hasLength(1));
        }
      } finally {
        semantics.dispose();
        await h.clean(t);
      }
    });
    testWidgets('$suite initial keyboard viewport read is static', (t) async {
      final h = Fixture();
      try {
        viewport(t, 1400);
        h.port.pending = Completer<void>();
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) => starBridgeInitialReadViewport(
                context,
                source: InteractionSource.keyboard,
                child: MenuSettingsWorkspace(draft: h.draft),
              ),
            ),
            suite,
          ),
        );
        await t.pump();
        await t.pump();
        expect(h.draft.busy, isTrue);
        expect(h.port.reads, 1);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(
          InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
              .reduceMotion,
          isTrue,
        );
        h.port.pending!.complete();
        await frames(t);
        expect(h.draft.ready, isTrue);
        expect(h.port.writes, 0);
      } finally {
        await h.clean(t);
      }
    });
    for (final input in ['pointer', 'keyboard']) {
      testWidgets('$suite $input ready but failed read keeps pending footer', (
        t,
      ) async {
        final h = Fixture();
        try {
          await mount(t, h, suite, width: 1400);
          h.port.failRead = true;
          await h.draft.reload();
          await frames(t);
          expect(h.draft.ready, isTrue);
          expect(h.draft.failed, isTrue);
          h.port.failRead = false;
          h.port.pending = Completer<void>();
          await key(t, input, 'menu-workspace-reload');
          expect(h.draft.failed, isFalse);
          expect(h.draft.ready, isTrue);
          expect(h.draft.busy, isTrue);
          expect(find.byType(SuiteBusyLabel), findsOneWidget);
          expect(
            InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
                .reduceMotion,
            input == 'keyboard',
          );
          expect(h.draft.dirty, isFalse);
          expect(h.port.writes, 0);
          h.port.pending!.complete();
          await frames(t);
          expect(find.byType(SuiteBusyLabel), findsNothing);
          expect(h.port.reads, 3);
          expect(h.port.writes, 0);
        } finally {
          await h.clean(t);
        }
      });
    }
    testWidgets(
      '$suite pending reload owner replacement isolates newer request',
      (t) async {
        final first = Fixture(), second = Fixture();
        try {
          first.port.failRead = true;
          final state = await mount(t, first, suite, width: 1400);
          first.port.pending = Completer<void>();
          first.port.failRead = false;
          await key(t, 'keyboard', 'menu-workspace-reload');
          second.port.failRead = true;
          state.change(() => state.draft = second.draft);
          await frames(t);
          expect(second.draft.failed, isTrue);
          second.port.pending = Completer<void>();
          second.port.failRead = false;
          await key(t, 'pointer', 'menu-workspace-reload');
          expect(second.draft.busy, isTrue);
          first.port.pending!.complete();
          await frames(t);
          expect(first.draft.ready, isTrue);
          expect(second.draft.busy, isTrue);
          expect(find.byType(SuiteBusyLabel), findsOneWidget);
          expect(
            InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
                .reduceMotion,
            isFalse,
          );
          second.port.pending!.complete();
          await frames(t);
          expect(second.draft.ready, isTrue);
          expect(first.port.reads, 2);
          expect(second.port.reads, 2);
          expect(first.port.writes, 0);
          expect(second.port.writes, 0);
          expect(t.takeException(), isNull);
        } finally {
          await first.clean(t);
          await second.clean(t);
        }
      },
    );
    for (final width in [430.0, 1100.0]) {
      for (final input in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $width $input selector preserves draft and independent editor',
          (t) async {
            final h = Fixture();
            final semantics = t.ensureSemantics();
            try {
              final state = await mount(t, h, suite, width: width);
              h.draft.change({'showClock': false});
              await frames(t);
              await choose(t, input, 'shortcuts');
              await t.enterText(
                find.byKey(const Key('independent-editor')),
                'local unsaved note',
              );
              await t.pump();
              final controller = t
                  .widget<TextField>(
                    find.byKey(const Key('independent-editor')),
                  )
                  .controller;
              await choose(t, input, 'browser');
              await choose(t, input, 'shortcuts');
              expect(
                t
                    .widget<TextField>(
                      find.byKey(const Key('independent-editor')),
                    )
                    .controller,
                same(controller),
              );
              expect(state.input.text, 'local unsaved note');
              expect(h.draft.settings['showClock'], isFalse);
              expect(h.draft.dirty, isTrue);
              expect(h.draft.canUndo, isTrue);
              expect(h.port.reads, 1);
              expect(h.port.writes, 0);
            } finally {
              semantics.dispose();
              await h.clean(t);
            }
          },
        );
      }
    }
    testWidgets('$suite section menu live reduce and Escape retain selection', (
      t,
    ) async {
      final h = Fixture();
      try {
        final state = await mount(t, h, suite);
        await key(t, 'pointer', 'menu-workspace-section-command');
        await t.pump(const Duration(milliseconds: 40));
        final a = t.widget<SuiteSurfaceTransition>(menus).animation;
        expect(a.value, inExclusiveRange(0, 1));
        state.change(() => state.reduce = true);
        await t.pump();
        await t.pump();
        expect(a.value, 1);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(menus, findsNothing);
        expect(
          find.byKey(const ValueKey('menu-section-display')),
          findsOneWidget,
        );
        expect(h.draft.dirty, isFalse);
        expect(h.port.writes, 0);
      } finally {
        await h.clean(t);
      }
    });
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final reject in [false, true]) {
        testWidgets(
          '$suite $input failed read retry reject=$reject stays truthful',
          (t) async {
            final h = Fixture();
            final semantics = t.ensureSemantics();
            try {
              h.port.failRead = true;
              await mount(t, h, suite, width: 1400);
              expect(h.draft.failed, isTrue);
              expect(h.draft.ready, isFalse);
              h.port.pending = Completer<void>();
              h.port.failRead = reject;
              await key(t, input, 'menu-workspace-reload');
              expect(h.port.reads, 2);
              expect(h.port.writes, 0);
              expect(
                h.port.sources.last,
                input == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(h.draft.busy, isTrue);
              expect(find.byType(SuiteBusyLabel), findsOneWidget);
              final busy = find.byType(SuiteBusyFrame);
              expect(
                InteractionScope.of(t.element(busy)).reduceMotion,
                input != 'pointer',
              );
              final retry = find.ancestor(
                of: find.byKey(const Key('menu-workspace-reload')),
                matching: find.byType(StarBridgeActionButton),
              );
              expect(
                t.widget<StarBridgeActionButton>(retry).onActivate,
                isNull,
              );
              await t.tap(find.byKey(const Key('menu-workspace-reload')));
              await t.pump();
              expect(h.port.reads, 2);
              h.port.pending!.complete();
              await frames(t);
              expect(h.draft.failed, reject);
              expect(h.draft.ready, !reject);
              expect(find.byType(SuiteBusyLabel), findsNothing);
              expect(
                find.byKey(const Key('menu-workspace-reload')),
                reject ? findsOneWidget : findsNothing,
              );
              expect(h.port.writes, 0);
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await h.clean(t);
            }
          },
        );
      }
    }
    testWidgets('$suite rejected dirty save never enables reload', (t) async {
      final h = Fixture();
      try {
        await mount(t, h, suite, width: 1400);
        h.draft.change({'showClock': false});
        h.port.failSave = true;
        expect(await h.draft.save(), isFalse);
        await frames(t);
        final button = find.ancestor(
          of: find.byKey(const Key('menu-workspace-reload')),
          matching: find.byType(StarBridgeActionButton),
        );
        expect(t.widget<StarBridgeActionButton>(button).onActivate, isNull);
        final reads = h.port.reads;
        await t.tap(find.byKey(const Key('menu-workspace-reload')));
        await t.pump();
        expect(h.port.reads, reads);
        expect(h.draft.dirty, isTrue);
        expect(h.draft.settings['showClock'], isFalse);
      } finally {
        await h.clean(t);
      }
    });
    testWidgets('$suite live reduction stops pending retry marker', (t) async {
      final h = Fixture();
      try {
        h.port.failRead = true;
        final state = await mount(t, h, suite, width: 1400);
        h.port.pending = Completer<void>();
        await key(t, 'pointer', 'menu-workspace-reload');
        await t.pump(const Duration(milliseconds: 40));
        state.change(() => state.reduce = true);
        await t.pump();
        await t.pump();
        expect(
          InteractionScope.of(t.element(find.byType(SuiteBusyFrame)))
              .reduceMotion,
          isTrue,
        );
        final count = h.port.reads;
        await frames(t);
        expect(h.port.reads, count);
        expect(h.port.writes, 0);
      } finally {
        await h.clean(t);
      }
    });
    for (final reject in [false, true]) {
      testWidgets(
        '$suite retry response after page leave reject=$reject remains owned',
        (t) async {
          final h = Fixture();
          try {
            h.port.failRead = true;
            final state = await mount(t, h, suite, width: 1400);
            h.port.pending = Completer<void>();
            h.port.failRead = reject;
            await key(t, 'keyboard', 'menu-workspace-reload');
            state.change(() => state.show = false);
            await t.pump();
            h.port.pending!.complete();
            await frames(t);
            state.change(() => state.show = true);
            await frames(t);
            expect(h.draft.failed, reject);
            expect(h.draft.ready, !reject);
            expect(h.port.reads, 2);
            expect(h.port.writes, 0);
            expect(find.byType(SuiteBusyLabel), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await h.clean(t);
          }
        },
      );
    }
    testWidgets(
      '$suite shared settings toggle keeps draft and keyboard is static',
      (t) async {
        final h = Fixture();
        final semantics = t.ensureSemantics();
        try {
          await mount(t, h, suite, width: 430);
          h.draft.change({'showClock': false});
          await frames(t);
          var shown = false;
          for (final input in ['pointer', 'keyboard', 'reader', 'pointer']) {
            await key(t, input, 'menu-settings-expand');
            await frames(t);
            shown = !shown;
            expect(
              find.byKey(const Key('menu-settings-right')),
              shown ? findsOneWidget : findsNothing,
            );
            expect(h.draft.dirty, isTrue);
            expect(h.port.writes, 0);
          }
          expect(h.port.reads, 1);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
          await h.clean(t);
        }
      },
    );
  }
}
