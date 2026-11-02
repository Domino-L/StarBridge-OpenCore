import 'dart:io';
import 'dart:convert';
import 'dart:ui' show SemanticsAction, ImageByteFormat, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_expansion_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_field.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_rules.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show size, loadFonts;
import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import '../../features/overlay_settings/overlay_appearance_preview_page_test.dart'
    show Workspace, appearance;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3u_test.dart' show choice;

OverlayWorkspaceSettings activeSettings() => settings({
  for (final f in overlayWorkspaceFieldSpecs.where(
    (f) => f.kind == OverlayWorkspaceFieldKind.toggle,
  ))
    f.field: true,
  'skin': 'Default',
  'theme': 'Default',
  'autoThemeByShip': false,
  'crosshairMode': 'Cross',
  'crosshairUseThemeColor': false,
  'chatDisplayMode': 'FullScreenBarrage',
});

Future<void> activateField(WidgetTester t, Key key, String source) async {
  final root = find.byKey(key);
  await t.ensureVisible(root);
  final target = t.widget(root);
  if (source == 'reader') {
    final menus = find.descendant(
      of: root,
      matching: find.byType(StarBridgeMenuAnchor),
    );
    final label = target is StarBridgeSwitch
        ? target.label
        : target is StarBridgeExpansionTile
        ? target.title
        : t.widget<StarBridgeMenuAnchor>(menus.first).semanticLabel;
    final nodes = exposedNodes(t)
        .where(
          (n) =>
              n.getSemanticsData().label == label &&
              n.getSemanticsData().hasAction(SemanticsAction.tap),
        )
        .toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
  } else if (source == 'keyboard') {
    final native = find.descendant(of: root, matching: find.byType(Switch));
    final suite = find.descendant(of: root, matching: find.byType(SuiteSwitch));
    if (native.evaluate().isNotEmpty) {
      t.widget<Switch>(native).focusNode!.requestFocus();
    } else if (suite.evaluate().isNotEmpty) {
      t.widget<SuiteSwitch>(suite).focusNode!.requestFocus();
    } else {
      final controls = find.descendant(
        of: root,
        matching: find.byType(FocusableActionDetector),
      );
      final owner = controls.evaluate().isEmpty
          ? null
          : t.widget<FocusableActionDetector>(controls.first).focusNode;
      (owner ??
              Focus.of(
                t.element(
                  find.descendant(of: root, matching: find.byType(Text)).first,
                ),
              ))
          .requestFocus();
    }
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await t.tap(
      target is StarBridgeExpansionTile
          ? find.descendant(of: root, matching: find.byType(Text)).first
          : root,
    );
  }
  await t.pump();
  await t.pump();
}

class FoldHarness extends StatefulWidget {
  const FoldHarness(this.suite, {super.key, this.maintainState = false});
  final InteractionSuite suite;
  final bool maintainState;
  @override
  State<FoldHarness> createState() => FoldState();
}

class FoldState extends State<FoldHarness> {
  bool visible = true, reduce = false;
  String identity = 'group-a';
  final text = TextEditingController(text: '保留原稿');
  final focus = FocusNode();
  int calls = 0, clicks = 0;
  void change(VoidCallback update) => setState(update);
  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => scopedApp(
    SizedBox(
      width: 360,
      child: visible
          ? StarBridgeExpansionTile(
              key: PageStorageKey(identity),
              title: '高级设置',
              subtitle: '保留当前工作区',
              maintainState: widget.maintainState,
              onExpansionChanged: (_) => calls++,
              children: [
                TextField(controller: text, focusNode: focus),
                TextButton(
                  onPressed: () => clicks++,
                  child: const Text('内容动作'),
                ),
              ],
            )
          : const Text('暂时移出'),
    ),
    widget.suite,
    reduce: reduce,
  );
}

void main() {
  setUpAll(loadFonts);
  final ready = activeSettings();
  final choices = overlayWorkspaceFieldSpecs
      .where(
        (f) =>
            f.userVisible &&
            [
              OverlayWorkspaceFieldKind.choice,
              OverlayWorkspaceFieldKind.numberChoice,
            ].contains(f.kind) &&
            overlayWorkspaceFieldVisible(f.field, ready) &&
            overlayWorkspaceFieldEnabled(f.field, ready),
      )
      .toList();
  final toggles = overlayWorkspaceFieldSpecs
      .where(
        (f) =>
            f.userVisible &&
            f.kind == OverlayWorkspaceFieldKind.toggle &&
            overlayWorkspaceFieldVisible(f.field, ready) &&
            overlayWorkspaceFieldEnabled(f.field, ready),
      )
      .toList();

  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source every visible mutable choice/toggle keeps exact callback and saves it',
        (t) async {
          size(t, const Size(1100, 900));
          final handle = t.ensureSemantics();
          final port = Workspace();
          final module = OverlayWorkspaceModule(port);
          await module.initialize();
          for (final entry in ready.toMap().entries) {
            module.updateSetting(entry.key, entry.value);
          }
          try {
            final visited = <String>{};
            for (final spec in [...choices, ...toggles]) {
              for (final entry in ready.toMap().entries) {
                module.updateSetting(entry.key, entry.value);
              }
              final events = <(String, Object?)>[];
              await t.pumpWidget(
                scopedApp(
                  ValueListenableBuilder(
                    valueListenable: module.projection,
                    builder: (_, p, _) => OverlayWorkspaceSettingsGroup(
                      group: spec.group,
                      fields: [spec],
                      settings: p.settings!,
                      appearances: p.snapshot!.appearances,
                      onChanged: (field, value) {
                        events.add((field, value));
                        module.updateSetting(field, value);
                      },
                    ),
                  ),
                  suite,
                ),
              );
              await t.pumpAndSettle();
              final key = Key('overlay-field-${spec.field}');
              expect(find.byKey(key), findsOneWidget, reason: spec.field);
              final before = module.projection.value.settings![spec.field];
              Object? requested;
              if (spec.kind == OverlayWorkspaceFieldKind.toggle) {
                requested = before != true;
                await activateField(t, key, source);
              } else {
                String label;
                if (spec.kind == OverlayWorkspaceFieldKind.choice) {
                  final field = t.widget<StarBridgeSelectField<String>>(
                    find.byKey(key),
                  );
                  final option =
                      field.options
                          .where((o) => o.enabled && o.value != before)
                          .lastOrNull ??
                      field.options.firstWhere((o) => o.enabled);
                  requested = option.value;
                  label = option.label;
                } else {
                  final field = t.widget<StarBridgeSelectField<num>>(
                    find.byKey(key),
                  );
                  final option = field.options.lastWhere(
                    (o) => o.enabled && o.value != before,
                  );
                  requested = option.value;
                  label = option.label;
                }
                await activateField(t, key, source);
                await t.pumpAndSettle();
                await choice(t, label, source);
              }
              await t.pumpAndSettle();
              expect(events, [(spec.field, requested)], reason: spec.field);
              expect(
                module.projection.value.settings![spec.field],
                requested,
                reason: spec.field,
              );
              expect(
                port.mutations.last.settings![spec.field],
                requested,
                reason: spec.field,
              );
              expect(t.takeException(), isNull, reason: spec.field);
              visited.add(spec.field);
            }
            expect(visited.length, choices.length + toggles.length);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            module.dispose();
            handle.dispose();
          }
        },
      );

      testWidgets(
        '$suite $source disclosure expanded semantics and instant nonpointer path',
        (t) async {
          size(t, const Size(900, 900));
          final handle = t.ensureSemantics();
          final key = GlobalKey<FoldState>();
          try {
            await t.pumpWidget(FoldHarness(suite, key: key));
            await t.pumpAndSettle();
            const header = PageStorageKey('group-a');
            await activateField(t, header, source);
            final node = exposedNodes(t).singleWhere(
              (n) =>
                  n.getSemanticsData().label == '高级设置' &&
                  n.getSemanticsData().hasAction(SemanticsAction.tap),
            );
            expect(
              node.getSemanticsData().flagsCollection.isExpanded,
              Tristate.isTrue,
            );
            expect(node.getSemanticsData().value, '保留当前工作区');
            if (source != 'pointer') {
              final reveal = find
                  .descendant(
                    of: find.byType(SuiteExpander),
                    matching: find.byType(Align),
                  )
                  .last;
              expect(t.widget<Align>(reveal).heightFactor, 1);
            }
            await t.pumpAndSettle();
            expect(find.byType(TextField), findsOneWidget);
            await activateField(t, header, source);
            await t.pumpAndSettle();
            expect(find.byType(TextField, skipOffstage: false), findsNothing);
            expect(key.currentState!.calls, 2);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            handle.dispose();
          }
        },
      );
    }

    for (final keep in [false, true]) {
      testWidgets(
        '$suite closing body loses focus/reader/hits before exit; maintainState=$keep',
        (t) async {
          size(t, const Size(900, 900));
          final handle = t.ensureSemantics();
          final key = GlobalKey<FoldState>();
          await t.pumpWidget(FoldHarness(suite, key: key, maintainState: keep));
          await t.pumpAndSettle();
          const header = PageStorageKey('group-a');
          await activateField(t, header, 'pointer');
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextField), '测试未保存草稿');
          expect(key.currentState!.focus.hasFocus, isTrue);
          await activateField(t, header, 'pointer');
          expect(key.currentState!.focus.hasFocus, isFalse);
          expect(
            exposedNodes(t).where((n) => n.getSemanticsData().label == '内容动作'),
            isEmpty,
          );
          expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
          // It still paints while leaving but IgnorePointer must block old hits.
          await t.tap(find.text('内容动作'), warnIfMissed: false);
          expect(key.currentState!.clicks, 0);
          await t.pumpAndSettle();
          expect(
            find.byType(TextField, skipOffstage: false),
            keep ? findsOneWidget : findsNothing,
          );
          await activateField(t, header, 'keyboard');
          await t.pumpAndSettle();
          expect(
            t.widget<TextField>(find.byType(TextField)).controller!.text,
            '测试未保存草稿',
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          handle.dispose();
        },
      );
    }

    testWidgets(
      '$suite PageStorage restores only matching group; reduction interrupts pointer reveal',
      (t) async {
        size(t, const Size(900, 900));
        final key = GlobalKey<FoldState>();
        await t.pumpWidget(FoldHarness(suite, key: key));
        await t.pumpAndSettle();
        await activateField(t, const PageStorageKey('group-a'), 'pointer');
        key.currentState!.change(() => key.currentState!.reduce = true);
        await t.pump();
        await t.pump();
        final reveal = find
            .descendant(
              of: find.byType(SuiteExpander),
              matching: find.byType(Align),
            )
            .last;
        expect(t.widget<Align>(reveal).heightFactor, 1);
        key.currentState!.change(() => key.currentState!.visible = false);
        await t.pumpAndSettle();
        key.currentState!.change(() => key.currentState!.visible = true);
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        expect(key.currentState!.calls, 1);
        key.currentState!.change(() => key.currentState!.identity = 'group-b');
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(key.currentState!.calls, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );

    testWidgets(
      '$suite prerequisite disables choice and preserves reader explanation',
      (t) async {
        size(t, const Size(1100, 900));
        final handle = t.ensureSemantics();
        await t.pumpWidget(
          scopedApp(
            OverlayWorkspaceSettingsGroup(
              group: 'crosshair',
              fields: overlayWorkspaceFieldSpecs
                  .where((f) => f.field == 'crosshairMode')
                  .toList(),
              settings: settings({'showCrosshair': false}),
              onChanged: (_, _) => fail('Disabled value wrote'),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        final selector = t.widget<StarBridgeSelectField<String>>(
          find.byKey(const Key('overlay-field-crosshairMode')),
        );
        expect(selector.onSelected, isNull);
        final anchor = t.widget<StarBridgeMenuAnchor>(
          find.byType(StarBridgeMenuAnchor),
        );
        final node = exposedNodes(t).singleWhere(
          (n) => n.getSemanticsData().label == anchor.semanticLabel,
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        expect(node.getSemanticsData().hint, selector.decoration.helperText);
        expect(node.getSemanticsData().hint, isNotEmpty);
        await t.tap(
          find.byKey(const Key('overlay-field-crosshairMode')),
          warnIfMissed: false,
        );
        await t.pumpAndSettle();
        expect(
          find.byKey(
            const ValueKey<Object>(('overlay-field-crosshairMode', 'Dot')),
          ),
          findsNothing,
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        handle.dispose();
      },
    );

    testWidgets(
      '$suite known retired theme is displayed but cannot be chosen; locked skin remains disabled',
      (t) async {
        size(t, const Size(1100, 900));
        final handle = t.ensureSemantics();
        final changes = <Object?>[];
        await t.pumpWidget(
          scopedApp(
            OverlayWorkspaceSettingsGroup(
              group: 'appearance',
              fields: overlayWorkspaceFieldSpecs
                  .where((f) => f.field == 'theme')
                  .toList(),
              settings: settings({'theme': 'Verdict'}),
              onChanged: (_, value) => changes.add(value),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        final selector = t.widget<StarBridgeSelectField<String>>(
          find.byKey(const Key('overlay-field-theme')),
        );
        expect(selector.value, 'Verdict');
        expect(
          selector.options.singleWhere((o) => o.value == 'Verdict').enabled,
          isFalse,
        );
        await activateField(t, const Key('overlay-field-theme'), 'keyboard');
        await t.pumpAndSettle();
        final node = exposedNodes(t)
            .where(
              (n) => n.getSemanticsData().label == selector.options.first.label,
            )
            .last;
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(changes, isEmpty);
        await t.pumpWidget(
          scopedApp(
            OverlayWorkspaceSettingsGroup(
              group: 'appearance',
              fields: overlayWorkspaceFieldSpecs
                  .where((f) => f.field == 'skin')
                  .toList(),
              settings: settings(),
              appearances: [appearance('Default'), appearance('NightShadow')],
              onChanged: (_, value) => changes.add(value),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        final skin = t.widget<StarBridgeSelectField<String>>(
          find.byKey(const Key('overlay-field-skin')),
        );
        expect(
          skin.options.singleWhere((o) => o.value == 'NightShadow').enabled,
          isFalse,
        );
        expect(changes, isEmpty);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        handle.dispose();
      },
    );
  }

  testWidgets('capture choices and disclosure at 420px/200% text', (t) async {
    size(t, const Size(420, 900));
    final frame = GlobalKey();
    for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
      await t.pumpWidget(
        scopedApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: RepaintBoundary(
                key: frame,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      OverlayWorkspaceSettingsGroup(
                        group: 'crosshair',
                        settings: ready,
                        fields: overlayWorkspaceFieldSpecs
                            .where(
                              (f) => [
                                'crosshairMode',
                                'crosshairShowCenterMark',
                              ].contains(f.field),
                            )
                            .toList(),
                        onChanged: (_, _) {},
                      ),
                      const StarBridgeExpansionTile(
                        key: PageStorageKey('capture-fold'),
                        title: '高级设置',
                        subtitle: '当前设置的说明与详细配置',
                        initiallyExpanded: true,
                        children: [
                          Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('展开中的原内容，不新增业务或保存状态。'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3V'] != null) {
        await t.runAsync(() async {
          final image =
              await (frame.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            final dir = Directory('build/reviews/interaction-batch3v');
            await dir.create(recursive: true);
            await File('${dir.path}/${suite.name}-fields-fold-large.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
    }
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3V'] != null) {
      await t.runAsync(
        () =>
            File('build/reviews/interaction-batch3v/field-coverage.json')
                .writeAsString(
                  jsonEncode({
                    'choices': choices.map((f) => f.field).toList(),
                    'toggles': toggles.map((f) => f.field).toList(),
                    'filter': 'userVisible && fieldVisible(activeSettings) && fieldEnabled(activeSettings)',
                    'state': 'Synthetic initial state; excluded conditional states remain independently listed, not marked accepted.',
                  }),
                ),
      );
    }
  });
}
