import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_field.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_settings_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_display_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_image_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_restore_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_screenshot_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_social_settings_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_toolbar_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_draft.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_settings_workspace.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_group_navigation.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_display_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_image_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_restore_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_social_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_toolbar_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_desktop_widgets.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3u_test.dart' show choice, target;
import 'interaction_batch3v_test.dart' show activateField;
import 'interaction_batch3m_test.dart' show activate;
import 'interaction_batch3b_test.dart' show exposedNodes;

const sections = [
  'display',
  'browser',
  'image',
  'screenshot',
  'restore',
  'social',
  'toolbar',
];
MenuWindowPreferences readyPreferences() =>
    MenuWindowPreferences.defaults.withSettingsPatch({
      ...const MenuDisplayPreferences(
        showContext: true,
        showClock: true,
      ).toSettingsPatch(),
      ...const MenuBrowserPreferences().toSettingsPatch(),
      ...const MenuImagePreferences().toSettingsPatch(),
      ...const MenuScreenshotPreferences(format: 'jpeg').toSettingsPatch(),
      ...const MenuRestorePreferences().toSettingsPatch(),
      ...const MenuSocialPreferences().toSettingsPatch(),
      'toolbar': const MenuToolbarPreferences().toMap(),
      'widgets': const MenuDesktopWidgets().toMap(),
    });

class Port implements MenuWindowPreferencesPort {
  MenuWindowPreferences value = readyPreferences();
  MenuWindowPreferences? submitted;
  Completer<MenuWindowPreferences>? pending;
  int writes = 0;
  bool fail = false;
  @override
  Future<MenuWindowPreferences> read() async => value;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences next) async {
    writes++;
    submitted = next;
    if (pending != null) return pending!.future;
    if (fail) throw StateError('fixture save rejected');
    return value = MenuWindowPreferences(
      next.revision + 1,
      next.layout,
      next.settings,
    );
  }
}

class Harness extends StatefulWidget {
  const Harness(this.draft, this.initial, {super.key, this.frameKey});
  final MenuSettingsDraft draft;
  final InteractionSuite initial;
  final GlobalKey? frameKey;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late var suite = widget.initial;
  var section = 'display', enabled = true, reduce = false, light = false;
  var scale = 1.0;
  int requests = 0;
  void change(VoidCallback fn) => setState(fn);
  void record(Map<String, Object?> patch) {
    requests++;
    widget.draft.change(patch);
  }

  @override
  Widget build(BuildContext context) => scopedApp(
    ListenableBuilder(
      listenable: widget.draft,
      builder: (_, _) {
        final d = widget.draft.settings, active = enabled && !widget.draft.busy;
        final editor = switch (section) {
          'browser' => MenuBrowserEditor(
            value: MenuBrowserPreferences.fromSettings(d)!,
            enabled: active,
            onChanged: (v) => record(v.toSettingsPatch()),
          ),
          'image' => MenuImageEditor(
            value: MenuImagePreferences.fromSettings(d)!,
            enabled: active,
            onChanged: (v) => record(v.toSettingsPatch()),
          ),
          'screenshot' => MenuScreenshotEditor(
            value: MenuScreenshotPreferences.fromSettings(d)!,
            enabled: active,
            onChanged: (v) => record(v.toSettingsPatch()),
          ),
          'restore' => MenuRestoreEditor(
            value: MenuRestorePreferences.fromSettings(d)!,
            enabled: active,
            onChanged: (v) => record(v.toSettingsPatch()),
          ),
          'social' => MenuSocialEditor(
            value: MenuSocialPreferences.fromSettings(d)!,
            enabled: active,
            onChanged: (v) => record(v.toSettingsPatch()),
          ),
          'toolbar' => MenuToolbarEditor(
            value: MenuToolbarPreferences.parse(d['toolbar'])!,
            enabled: active,
            onChanged: (v) => record({'toolbar': v.toMap()}),
          ),
          _ => MenuDisplayEditor(
            value: MenuDisplayPreferences.fromSettings(d)!,
            enabled: active,
            widgets: MenuDesktopWidgets.parse(d['widgets'])!,
            onWidgetsChanged: (v) => record({'widgets': v.toMap()}),
            onChanged: (v) => record(v.toSettingsPatch()),
          ),
        };
        return MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: RepaintBoundary(key: widget.frameKey, child: editor),
              ),
            ),
          ),
        );
      },
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<(GlobalKey<HarnessState>, Port, MenuSettingsDraft)> mount(
  WidgetTester t,
  InteractionSuite suite,
) async {
  size(t, const Size(1000, 1000));
  final port = Port();
  final owner = MenuSettingsDraft(port);
  addTearDown(owner.dispose);
  await owner.initialize();
  final key = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(owner, suite, key: key));
  await t.pumpAndSettle();
  return (key, port, owner);
}

List<StarBridgeSelectField<dynamic>> selects(WidgetTester t) => t
    .widgetList<StarBridgeSelectField<dynamic>>(
      find.byWidgetPredicate((w) => w is StarBridgeSelectField),
    )
    .toList();

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source every menu editor select/toggle calls real draft once',
        (t) async {
          final sem = t.ensureSemantics();
          final (key, port, draft) = await mount(t, suite);
          final state = key.currentState!;
          final seenChoices = <String>{}, seenToggles = <String>{};
          try {
            for (final section in sections) {
              draft.discard();
              state.change(() => state.section = section);
              await t.pumpAndSettle();
              final fields = selects(t).map((f) => f.key!).toList();
              final toggles = t
                  .widgetList<StarBridgeSwitch>(find.byType(StarBridgeSwitch))
                  .map((f) => f.key!)
                  .toList();
              for (final fieldKey in fields) {
                draft.discard();
                await t.pumpAndSettle();
                final field = t.widget<StarBridgeSelectField<dynamic>>(
                  find.byKey(fieldKey),
                );
                final option = field.options.lastWhere(
                  (o) => o.enabled && o.value != field.value,
                );
                final before = state.requests;
                await target(t, fieldKey, source);
                final transition = t.widget<SuiteSurfaceTransition>(
                  find.byType(SuiteSurfaceTransition).last,
                );
                if (source != 'pointer') {
                  expect(transition.animation.value, 1);
                }
                await t.pumpAndSettle();
                await choice(t, option.label, source);
                await t.pumpAndSettle();
                expect(
                  state.requests,
                  before + 1,
                  reason: '$section $fieldKey',
                );
                expect(
                  t
                      .widget<StarBridgeSelectField<dynamic>>(
                        find.byKey(fieldKey),
                      )
                      .value,
                  option.value,
                );
                expect(draft.dirty, isTrue);
                expect(port.writes, 0);
                seenChoices.add(field.identity.toString());
              }
              for (final controlKey in toggles) {
                draft.discard();
                await t.pumpAndSettle();
                final field = t.widget<StarBridgeSwitch>(
                  find.byKey(controlKey),
                );
                expect(
                  field.onChanged,
                  isNotNull,
                  reason: '$section $controlKey',
                );
                final before = state.requests;
                await activateField(t, controlKey, source);
                await t.pumpAndSettle();
                expect(
                  state.requests,
                  before + 1,
                  reason: '$section $controlKey',
                );
                expect(
                  t.widget<StarBridgeSwitch>(find.byKey(controlKey)).value,
                  !field.value,
                );
                expect(draft.dirty, isTrue);
                expect(port.writes, 0);
                seenToggles.add(controlKey.toString());
              }
            }
            expect(seenChoices, hasLength(13));
            expect(seenToggles, hasLength(37));
            expect(MenuWindowPreferences.parse(port.value.toMap()), isNotNull);
            expect(t.takeException(), isNull);
            await t.runAsync(() async {
              final dir = Directory('build/reviews/interaction-batch3x')
                ..createSync(recursive: true);
              File('${dir.path}/field-coverage.txt').writeAsStringSync(
                [
                  'choices=${seenChoices.length}',
                  ...seenChoices,
                  'toggles=${seenToggles.length}',
                  ...seenToggles,
                ].join('\n'),
              );
            });
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            sem.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite dependencies and disabled editor never reopen an overlay',
      (t) async {
        final sem = t.ensureSemantics();
        final (key, _, draft) = await mount(t, suite);
        try {
          draft.change(
            const MenuDisplayPreferences(
              showClock: false,
              showContext: false,
              streamerPrivacy: true,
            ).toSettingsPatch(),
          );
          await t.pumpAndSettle();
          expect(
            t
                .widget<StarBridgeSelectField<String>>(
                  find.byKey(const Key('menu-display-format')),
                )
                .onSelected,
            isNull,
          );
          for (final id in [
            'showScene',
            'showMembers',
            'showShip',
            'showLocation',
            'showServer',
            'showRoomCode',
          ]) {
            expect(
              t
                  .widget<StarBridgeSwitch>(find.byKey(Key('menu-display-$id')))
                  .onChanged,
              isNull,
            );
          }
          key.currentState!.change(() => key.currentState!.section = 'social');
          draft.change(
            const MenuSocialPreferences(notifications: false).toSettingsPatch(),
          );
          await t.pumpAndSettle();
          expect(
            t
                .widget<StarBridgeSelectField<String>>(
                  find.byKey(const Key('menu-social-preview')),
                )
                .onSelected,
            isNull,
          );
          expect(
            t
                .widget<StarBridgeSwitch>(
                  find.byKey(const Key('menu-social-sound')),
                )
                .onChanged,
            isNull,
          );
          for (final section in sections) {
            key.currentState!.change(() {
              key.currentState!.section = section;
              key.currentState!.enabled = false;
            });
            await t.pumpAndSettle();
            for (final field in selects(t)) {
              expect(field.onSelected, isNull);
            }
            for (final field in t.widgetList<StarBridgeSwitch>(
              find.byType(StarBridgeSwitch),
            )) {
              expect(field.onChanged, isNull);
            }
            for (final field in t.widgetList<Slider>(find.byType(Slider))) {
              expect(field.onChanged, isNull);
            }
            for (final node in exposedNodes(t)) {
              if (node.getSemanticsData().flagsCollection.isEnabled ==
                  Tristate.isFalse) {
                expect(
                  node.getSemanticsData().hasAction(SemanticsAction.tap),
                  isFalse,
                );
              }
            }
          }
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          sem.dispose();
        }
      },
    );
    testWidgets(
      '$suite three native sliders update, undo/redo and save only on request',
      (t) async {
        final (key, port, draft) = await mount(t, suite);
        for (final section in ['display', 'image', 'screenshot']) {
          final previousWrites = port.writes;
          draft.discard();
          key.currentState!.change(() => key.currentState!.section = section);
          await t.pumpAndSettle();
          final slider = find.byType(Slider);
          await t.ensureVisible(slider);
          final before = key.currentState!.requests;
          final gesture = await t.startGesture(t.getCenter(slider));
          for (var i = 0; i < 5; i++) {
            await gesture.moveBy(const Offset(-35, 0));
            await t.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
          await t.pumpAndSettle();
          expect(key.currentState!.requests, greaterThanOrEqualTo(before + 5));
          expect(draft.dirty, isTrue);
          expect(port.writes, previousWrites);
          final projected = Map<String, Object?>.of(draft.settings);
          draft.undo();
          expect(draft.canRedo, isTrue);
          draft.redo();
          expect(draft.settings, projected);
          await draft.save();
          await t.pumpAndSettle();
          expect(draft.dirty, isFalse);
          expect(port.value.layout, readyPreferences().layout);
        }
        expect(port.writes, 3);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite active repeated toggles and toolbar move/reset retain feedback',
      (t) async {
        final (key, port, draft) = await mount(t, suite);
        key.currentState!.change(() => key.currentState!.section = 'toolbar');
        await t.pumpAndSettle();
        const control = Key('menu-toolbar-unread');
        final before = key.currentState!.requests;
        for (var i = 0; i < 6; i++) {
          await activateField(t, control, 'pointer');
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(key.currentState!.requests, before + 6);
        if (suite != InteractionSuite.standard) {
          final field = t.widget<SuiteSwitch>(
            find.descendant(
              of: find.byKey(control),
              matching: find.byType(SuiteSwitch),
            ),
          );
          expect(field.value, isTrue);
          final paint = t
              .widgetList<CustomPaint>(
                find.descendant(
                  of: find.byKey(control),
                  matching: find.byType(CustomPaint),
                ),
              )
              .firstWhere(
                (p) => p.painter.runtimeType.toString() == '_SwitchPainter',
              );
          if (suite == InteractionSuite.scan) {
            // The approved scan knob snaps; the beam/brackets supply feedback.
            final effect = t
                .widgetList<CustomPaint>(
                  find.descendant(
                    of: find.byKey(control),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .firstWhere(
                  (p) =>
                      p.foregroundPainter.runtimeType.toString() ==
                      '_EffectPainter',
                );
            var repaints = 0;
            void tick() => repaints++;
            effect.foregroundPainter!.addListener(tick);
            try {
              await t.pump(const Duration(milliseconds: 20));
              expect(repaints, greaterThan(0));
            } finally {
              effect.foregroundPainter!.removeListener(tick);
            }
          } else {
            expect(
              ((paint.painter as dynamic).t as AnimationController).isAnimating,
              isTrue,
              reason: 'Rapid active clicks retain interruptible feedback.',
            );
          }
        }
        await t.pumpAndSettle();
        final items = find.byType(StarBridgeIconAction);
        final old = MenuToolbarPreferences.parse(draft.settings['toolbar'])!
            .order;
        await t.ensureVisible(items.at(1));
        final action = t.widget<StarBridgeIconAction>(items.at(1));
        Focus.of(
          t.element(
            find.descendant(
              of: items.at(1),
              matching: find.byWidget(action.icon),
            ),
          ),
        ).requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        final order = MenuToolbarPreferences.parse(draft.settings['toolbar'])!
            .order;
        expect(order[0], old[1]);
        expect(order[1], old[0]);
        await activate(
          t,
          find.byKey(const Key('menu-toolbar-reset')),
          'pointer',
        );
        await t.pumpAndSettle();
        expect(
          MenuToolbarPreferences.parse(draft.settings['toolbar'])!.order,
          MenuToolbarPreferences.ids,
        );
        expect(port.writes, 0);
        expect(t.takeException(), isNull);
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source real shared save rejection, retry and live busy gate',
        (t) async {
          size(t, const Size(900, 1000));
          final sem = t.ensureSemantics();
          final port = Port();
          try {
            await t.pumpWidget(
              scopedApp(
                SingleChildScrollView(
                  child: MenuBrowserSettingsCard(port: port),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await target(t, const Key('menu-browser-provider'), source);
            await t.pumpAndSettle();
            final field = t.widget<StarBridgeSelectField<String>>(
              find.byKey(const Key('menu-browser-provider')),
            );
            final option = field.options.lastWhere(
              (o) => o.value != field.value,
            );
            await choice(t, option.label, source);
            await t.pumpAndSettle();
            final obsoleteSelection = t
                .widget<StarBridgeSelectField<String>>(
                  find.byKey(const Key('menu-browser-provider')),
                )
                .onSelected!;
            port.pending = Completer();
            await target(t, const Key('menu-browser-save'), source);
            await t.pump();
            expect(port.writes, 1);
            obsoleteSelection(field.value!, InteractionSource.pointer);
            await t.pump();
            expect(
              t
                  .widget<StarBridgeSelectField<String>>(
                    find.byKey(const Key('menu-browser-provider')),
                  )
                  .value,
              option.value,
            );
            expect(
              t
                  .widget<StarBridgeSelectField<String>>(
                    find.byKey(const Key('menu-browser-provider')),
                  )
                  .onSelected,
              isNull,
            );
            expect(
              t
                  .widget<StarBridgeActionButton>(
                    find.byKey(const Key('menu-browser-save')),
                  )
                  .onActivate,
              isNull,
            );
            final snapshot = port.submitted!;
            port.pending!.completeError(StateError('fixture rejected'));
            port.pending = null;
            await t.pumpAndSettle();
            expect(find.byKey(const Key('menu-browser-error')), findsOneWidget);
            expect(
              t
                  .widget<StarBridgeSelectField<String>>(
                    find.byKey(const Key('menu-browser-provider')),
                  )
                  .value,
              option.value,
            );
            expect(port.value.settings, readyPreferences().settings);
            await target(t, const Key('menu-browser-save'), source);
            await t.pumpAndSettle();
            expect(port.writes, 2);
            expect(port.value.settings, snapshot.settings);
            expect(port.value.layout, snapshot.layout);
            expect(find.byKey(const Key('menu-browser-error')), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            sem.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite open menu follows reduce/theme, disabled before rebuild callback is guarded',
      (t) async {
        final (key, port, draft) = await mount(t, suite);
        key.currentState!.change(() => key.currentState!.section = 'browser');
        await t.pumpAndSettle();
        await target(t, const Key('menu-browser-provider'), 'pointer');
        key.currentState!.change(() {
          key.currentState!.reduce = true;
          key.currentState!.light = true;
        });
        await t.pump();
        await t.pump();
        expect(
          t
              .widget<SuiteSurfaceTransition>(
                find.byType(SuiteSurfaceTransition).last,
              )
              .animation
              .value,
          1,
        );
        draft.change(
          const MenuBrowserPreferences(openLinksInNewTab: false)
              .toSettingsPatch(),
        );
        port.pending = Completer();
        final saving = draft.save();
        await t.pump();
        await t.pump();
        expect(find.byType(SuiteSurfaceTransition), findsNothing);
        final submitted = port.submitted!;
        draft.change(
          const MenuBrowserPreferences(provider: 'bing').toSettingsPatch(),
        );
        expect(draft.settings, submitted.settings);
        port.pending!.complete(submitted);
        await saving;
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite owner replacement ignores late response; unmount does not write again',
      (t) async {
        size(t, const Size(900, 1000));
        final old = Port(), next = Port();
        Widget app(Port port) => scopedApp(
          SingleChildScrollView(child: MenuBrowserSettingsCard(port: port)),
          suite,
        );
        await t.pumpWidget(app(old));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('menu-browser-links')));
        await t.pumpAndSettle();
        old.pending = Completer();
        await target(t, const Key('menu-browser-save'), 'pointer');
        await t.pump();
        await t.pumpWidget(app(next));
        await t.pumpAndSettle();
        old.pending!.completeError(StateError('late old owner rejection'));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('menu-browser-error')), findsNothing);
        expect(
          t
              .widget<MenuBrowserEditor>(find.byType(MenuBrowserEditor))
              .value
              .openLinksInNewTab,
          isTrue,
        );
        await t.tap(find.byKey(const Key('menu-browser-links')));
        await t.pumpAndSettle();
        next.pending = Completer();
        await target(t, const Key('menu-browser-save'), 'pointer');
        await t.pump();
        await t.pumpWidget(const SizedBox());
        next.pending!.complete(next.submitted!);
        await t.pumpAndSettle();
        expect(old.writes, 1);
        expect(next.writes, 1);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite real workspace hides old menu when switching sections',
      (t) async {
        size(t, const Size(1280, 1000));
        final port = Port();
        final owner = MenuSettingsDraft(port);
        addTearDown(owner.dispose);
        await t.pumpWidget(
          scopedApp(MenuSettingsWorkspace(draft: owner), suite),
        );
        await t.pumpAndSettle();
        await target(t, const Key('menu-display-interfaceScale'), 'pointer');
        await t.pumpAndSettle();
        expect(find.byType(SuiteSurfaceTransition), findsOneWidget);
        final navigation = find.byKey(const Key('menu-group-navigation'));
        await t.tap(
          find.descendant(of: navigation, matching: find.text('浏览器')),
        );
        await t.pumpAndSettle();
        expect(find.byType(SuiteSurfaceTransition), findsNothing);
        expect(port.writes, 0);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final suite in InteractionSuite.values) {
    for (final reduce in [false, true]) {
      testWidgets(
        '$suite reduce=$reduce rapid section reversal retires only local menu and keeps draft',
        (t) async {
          size(t, const Size(1280, 1000));
          final sem = t.ensureSemantics();
          final port = Port();
          final owner = MenuSettingsDraft(port);
          addTearDown(owner.dispose);
          try {
            await t.pumpWidget(
              scopedApp(
                MenuSettingsWorkspace(draft: owner),
                suite,
                reduce: reduce,
              ),
            );
            await t.pumpAndSettle();
            owner.change(
              const MenuImagePreferences(opacityPercent: 35).toSettingsPatch(),
            );
            await t.pumpAndSettle();
            final before = Map<String, Object?>.of(owner.settings);
            for (final visited in ['image', 'screenshot', 'display']) {
              t
                  .widget<OverlayWorkspaceGroupNavigation>(
                    find.byType(OverlayWorkspaceGroupNavigation),
                  )
                  .onSelected(visited);
              await t.pumpAndSettle();
            }
            await target(
              t,
              const Key('menu-display-interfaceScale'),
              'keyboard',
            );
            await t.pumpAndSettle();
            final nav = t.widget<OverlayWorkspaceGroupNavigation>(
              find.byType(OverlayWorkspaceGroupNavigation),
            );
            nav.onSelected('browser');
            nav.onSelected('image');
            nav.onSelected('browser');
            await t.pump();
            expect(
              t
                  .widget<OverlayWorkspaceGroupNavigation>(
                    find.byType(OverlayWorkspaceGroupNavigation),
                  )
                  .selected,
              'browser',
            );
            await t.pump();
            await t.pumpAndSettle();
            // The retained dirty SaveBar also uses a surface transition. This
            // test retires the local menu, not that deliberately visible bar.
            expect(
              find.byWidgetPredicate(
                (w) =>
                    w is SuiteSurfaceTransition && w.kind == SurfaceKind.menu,
              ),
              findsNothing,
            );
            expect(find.byType(AlertDialog), findsNothing);
            expect(
              find.byKey(const Key('menu-settings-save-bar')),
              findsOneWidget,
            );
            final anchors = t
                .widgetList<RawMenuAnchor>(
                  find.byType(RawMenuAnchor, skipOffstage: false),
                )
                .toList();
            expect(anchors, isNotEmpty);
            for (final anchor in anchors) {
              expect(anchor.controller.isOpen, false);
            }
            expect(find.byType(MenuBrowserEditor), findsOneWidget);
            expect(owner.settings, before);
            expect(owner.dirty, isTrue);
            expect(port.writes, 0);
            expect(t.takeException(), isNull);
            port.pending = Completer();
            final save = owner.save();
            await t.pump();
            await t.pump();
            expect(t.takeException(), isNull);
            port.pending!.completeError(
              StateError('fixture refused while inactive controls exist'),
            );
            await save;
            await t.pumpAndSettle();
            expect(owner.settings, before);
            expect(owner.dirty, isTrue);
            expect(owner.failed, isTrue);
            expect(port.writes, 1);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            sem.dispose();
          }
        },
      );
    }
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('$suite review 200 percent menu text and controls', (t) async {
      size(t, const Size(700, 1200));
      final port = Port();
      final draft = MenuSettingsDraft(port);
      addTearDown(draft.dispose);
      await draft.initialize();
      final key = GlobalKey<HarnessState>(), frame = GlobalKey();
      await t.pumpWidget(Harness(draft, suite, key: key, frameKey: frame));
      key.currentState!.change(() {
        key.currentState!.section = 'browser';
        key.currentState!.scale = 2;
      });
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final boundary =
            frame.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await boundary.toImage();
        try {
          final bytes = (await img.toByteData(format: ImageByteFormat.png))!;
          final dir = Directory('build/reviews/interaction-batch3x')
            ..createSync(recursive: true);
          File('${dir.path}/${suite.name}-menu-200.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        } finally {
          img.dispose();
        }
      });
      expect(t.takeException(), isNull);
    });
  }
}
