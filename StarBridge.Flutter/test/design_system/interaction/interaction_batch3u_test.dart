import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_field.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_color_picker.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration_panel.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_options.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_live_session.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_preview_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/overlay_settings/overlay_appearance_configuration_test.dart'
    as config;
import '../../features/overlay_settings/overlay_appearance_center_entry_test.dart'
    show EntryPort;
import '../../features/overlay_settings/overlay_appearance_preview_page_test.dart'
    show Workspace;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3m_test.dart' show activate;
import 'interaction_batch3b_test.dart' show semanticTap, exposedNodes;
import 'interaction_batch3t_test.dart' as prior show target;

Future<void> choice(WidgetTester t, String label, String source) async {
  final key = find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\$')).last;
  if (source == 'reader') {
    await semanticTap(t, key);
    await t.pump();
  } else {
    // Menu rows have a real focus node and stable value identity.
    await activate(
      t,
      find
          .ancestor(
            of: find.text(label).last,
            matching: find.byWidgetPredicate(
              (w) => w is MenuItemButton || w is SuitePressable,
            ),
          )
          .first,
      source,
    );
  }
}

Future<void> target(WidgetTester t, Key key, String source) async {
  if (source == 'keyboard') {
    final root = find.byKey(key);
    final menus = find.descendant(
      of: root,
      matching: find.byType(StarBridgeMenuAnchor),
    );
    if (menus.evaluate().isNotEmpty) {
      expect(menus, findsOneWidget);
      await t.ensureVisible(root);
      final row = find.descendant(
        of: root,
        matching: find.byType(StarBridgeActionRow),
      );
      expect(row, findsOneWidget);
      final focus = t.widget<StarBridgeActionRow>(row).focusNode;
      expect(focus, isNotNull);
      expect(focus!.canRequestFocus, isTrue);
      focus.requestFocus();
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(focus));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      await t.pump();
      return;
    }
  }
  if (source != 'reader') return prior.target(t, key, source);
  final root = find.byKey(key);
  await t.ensureVisible(root);
  final menus = find.descendant(
    of: root,
    matching: find.byType(StarBridgeMenuAnchor),
  );
  final label = menus.evaluate().isNotEmpty
      ? t.widget<StarBridgeMenuAnchor>(menus.first).semanticLabel
      : t.widget<StarBridgeActionButton>(root).semanticLabel!;
  final nodes = exposedNodes(t)
      .where(
        (node) =>
            node.getSemanticsData().label == label &&
            node.getSemanticsData().hasAction(SemanticsAction.tap),
      )
      .toList();
  expect(nodes, hasLength(1));
  t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    nodes.single.id,
    SemanticsAction.tap,
  );
  await t.pump();
  await t.pump();
}

class ColorHarness extends StatefulWidget {
  const ColorHarness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<ColorHarness> createState() => ColorHarnessState();
}

class ColorHarnessState extends State<ColorHarness> {
  bool visible = true, enabled = true, reduce = false, light = false;
  String value = '#FFFFFF';
  Object? owner = Object();
  final changes = <String>[];
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    SizedBox(
      width: 320,
      child: visible
          ? OverlayColorField(
              label: '准星颜色',
              value: value,
              editOwner: owner,
              currentEditOwner: () => owner,
              onChanged: enabled
                  ? (next) {
                      changes.add(next);
                      setState(() => value = next);
                    }
                  : null,
            )
          : const Text('其他设置'),
    ),
    widget.suite,
    reduce: reduce,
    light: light,
  );
}

class ProtectedPort
    implements
        OverlayAppearanceLivePort,
        OverlayAppearanceLiveControlsPort,
        OverlayAppearanceLivePlaybackPort {
  ProtectedPort(this.base);
  final EntryPort base;
  Completer<void>? holdFullProtection;
  int fullRequests = 0;
  @override
  Future<String> openLivePreview(OverlayAppearanceLiveFrame f) =>
      base.openLivePreview(f);
  @override
  Future<int> updateLivePreview(
    String id,
    int revision,
    OverlayAppearanceLiveFrame f,
  ) => base.updateLivePreview(id, revision, f);
  @override
  Future<void> closeLivePreview(String id) => base.closeLivePreview(id);
  @override
  Future<int> renewLivePreview(String id, int revision) =>
      base.renewLivePreview(id, revision);
  @override
  Future<bool> playLivePreview(
    String id,
    int revision,
    OverlayAppearancePreviewPlayback a,
  ) => base.playLivePreview(id, revision, a);
  @override
  Future<int> protectLivePreviewControls(
    String id,
    int revision,
    List<OverlayPreviewControlArea> areas,
  ) async {
    if (areas.length == 1 &&
        areas.single.width == 1 &&
        areas.single.height == 1) {
      fullRequests++;
      await holdFullProtection?.future;
    }
    return base.protectLivePreviewControls(id, revision, areas);
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source color validates, applies once, retains immediate input origin',
        (t) async {
          size(t, const Size(900, 900));
          final handle = t.ensureSemantics();
          final key = GlobalKey<ColorHarnessState>();
          try {
            await t.pumpWidget(ColorHarness(suite, key: key));
            await t.pumpAndSettle();
            await target(t, const Key('overlay-color-open'), source);
            final route =
                ModalRoute.of(t.element(find.byType(OverlayColorPickerDialog)))!
                    as StarBridgeDialogRoute<String>;
            expect(route.instant, source != 'pointer');
            await t.pumpAndSettle();
            await t.enterText(
              find.byKey(const Key('overlay-color-hex')),
              '#12',
            );
            await t.pump();
            expect(
              t
                  .widget<StarBridgeActionButton>(
                    find.byKey(const Key('overlay-color-apply')),
                  )
                  .onActivate,
              isNull,
            );
            expect(key.currentState!.changes, isEmpty);
            await t.enterText(
              find.byKey(const Key('overlay-color-hex')),
              '#ab12ef',
            );
            await t.pump();
            await activate(
              t,
              find.byKey(const Key('overlay-color-apply')),
              source,
            );
            await t.pumpAndSettle();
            expect(key.currentState!.changes, ['#AB12EF']);
            expect(find.byType(OverlayColorPickerDialog), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            handle.dispose();
          }
        },
      );

      testWidgets(
        '$suite $source configuration menus retain controlled draft and final semantics',
        (t) async {
          size(t, const Size(900, 900));
          final handle = t.ensureSemantics();
          final c = OverlayAppearanceConfiguration.fromMap(
            config.withGlobalField(),
          );
          var options = const OverlayAppearanceOptions.empty();
          var changes = 0;
          try {
            await t.pumpWidget(
              scopedApp(
                SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (_, update) => OverlayAppearanceConfigurationPanel(
                      configuration: c,
                      options: options,
                      onChanged: (value) => update(() {
                        options = value;
                        changes++;
                      }),
                    ),
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await target(
              t,
              const Key('appearance-config-global-backdrop'),
              source,
            );
            await t.pumpAndSettle();
            await choice(t, 'Black', source);
            await t.pumpAndSettle();
            expect(c.readFields(options), {'backdrop': true});
            await target(t, const Key('appearance-config-slot-slot0'), source);
            await t.pumpAndSettle();
            await choice(t, 'Variant 1', source);
            await t.pumpAndSettle();
            await target(
              t,
              const Key('appearance-config-field-slot0-color'),
              source,
            );
            await t.pumpAndSettle();
            await choice(t, 'Color 1', source);
            await t.pumpAndSettle();
            expect(c.read(options)!['slot0']!['color'], 1);
            expect(changes, 3);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            handle.dispose();
          }
        },
      );

      testWidgets(
        '$suite $source native skin menu stays in protected panel; color waits for protection',
        (t) async {
          size(t, const Size(1280, 900));
          final handle = t.ensureSemantics();
          final base = EntryPort(configurations: []);
          final port = ProtectedPort(base);
          final module = OverlayWorkspaceModule(base);
          await module.initialize();
          module.updateSetting('showCrosshair', true);
          module.updateSetting('crosshairUseThemeColor', false);
          final before = module.projection.value.settings!.toMap();
          try {
            await t.pumpWidget(
              scopedApp(
                OverlayAppearancePreviewPage(
                  module: module,
                  port: port,
                  appearanceId: 'Verdict',
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await target(t, const Key('appearance-preview-skin'), source);
            await t.pumpAndSettle();
            final row = find.byKey(
              const ValueKey<Object>(('appearance-preview-skin', 'Default')),
            );
            final rect = t.getRect(row);
            final area = base.live.protections.last.firstWhere(
              (a) => a.height == 1,
            );
            expect(rect.left, greaterThanOrEqualTo(area.x * 1280));
            expect(rect.right, lessThanOrEqualTo((area.x + area.width) * 1280));
            await choice(t, '舰队标准', source);
            await t.pumpAndSettle();
            expect(base.live.updates.last.appearanceId, 'Default');
            expect(module.projection.value.settings!.toMap(), before);
            expect(base.storage.mutations, hasLength(1)); // only the setup edits
            await t.tap(find.byKey(const Key('appearance-preview-crosshair')));
            await t.pumpAndSettle();
            port.holdFullProtection = Completer<void>();
            await activate(
              t,
              find.byKey(const Key('appearance-preview-color-crosshairColor')),
              source,
            );
            expect(port.fullRequests, 1);
            expect(find.byType(OverlayColorPickerDialog), findsNothing);
            port.holdFullProtection!.complete();
            await t.pumpAndSettle();
            expect(find.byType(OverlayColorPickerDialog), findsOneWidget);
            await t.enterText(
              find.byKey(const Key('overlay-color-hex')),
              '#123456',
            );
            await activate(
              t,
              find.byKey(const Key('overlay-color-cancel')),
              source,
            );
            await t.pumpAndSettle();
            expect(module.projection.value.settings!.toMap(), before);
            expect(base.live.protections.last.length, greaterThan(1));
            expect(base.storage.mutations, hasLength(1)); // only the setup edits
            expect(t.takeException(), isNull);
          } finally {
            port.holdFullProtection?.completeIfNeeded();
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            module.dispose();
            handle.dispose();
          }
        },
      );
    }

    for (final missing in [false, true]) {
      testWidgets(
        '$suite apply racing owner ${missing ? 'loss' : 'replacement'} before rebuild is rejected',
        (t) async {
          size(t, const Size(900, 900));
          final handle = t.ensureSemantics();
          final key = GlobalKey<ColorHarnessState>();
          await t.pumpWidget(ColorHarness(suite, key: key));
          await t.pumpAndSettle();
          await target(t, const Key('overlay-color-open'), 'pointer');
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('overlay-color-hex')),
            '#123456',
          );
          await t.pump();
          final label = t
              .widget<Text>(
                find
                    .descendant(
                      of: find.byKey(const Key('overlay-color-apply')),
                      matching: find.byType(Text),
                    )
                    .first,
              )
              .data!;
          final node = t.getSemantics(find.bySemanticsLabel(label).last);
          t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
            node.id,
            SemanticsAction.tap,
          );
          // No frame/microtask in between: the old widget is still mounted.
          key.currentState!.change(
            () => key.currentState!.owner = missing ? null : Object(),
          );
          await t.pumpAndSettle();
          expect(key.currentState!.changes, isEmpty);
          expect(key.currentState!.value, '#FFFFFF');
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          handle.dispose();
        },
      );
    }
    for (final stage in ['protected-pending', 'dialog-open']) {
      testWidgets(
        '$suite native $stage workspace replacement cannot apply old color',
        (t) async {
          size(t, const Size(1280, 900));
          final base = EntryPort(configurations: []);
          final port = ProtectedPort(base);
          final module = OverlayWorkspaceModule(base);
          await module.initialize();
          module.updateSetting('showCrosshair', true);
          module.updateSetting('crosshairUseThemeColor', false);
          await t.pumpWidget(
            scopedApp(
              OverlayAppearancePreviewPage(
                module: module,
                port: port,
                appearanceId: 'Default',
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('appearance-preview-crosshair')));
          await t.pumpAndSettle();
          if (stage == 'protected-pending') {
            port.holdFullProtection = Completer<void>();
          }
          await activate(
            t,
            find.byKey(const Key('appearance-preview-color-crosshairColor')),
            'pointer',
          );
          if (stage == 'dialog-open') {
            await t.pumpAndSettle();
            expect(find.byType(OverlayColorPickerDialog), findsOneWidget);
            await t.enterText(
              find.byKey(const Key('overlay-color-hex')),
              '#123456',
            );
          } else {
            expect(find.byType(OverlayColorPickerDialog), findsNothing);
          }
          base.storage.snapshot = Workspace().snapshot;
          await module.refresh();
          port.holdFullProtection?.completeIfNeeded();
          await t.pumpAndSettle();
          expect(find.byType(OverlayColorPickerDialog), findsNothing);
          expect(base.storage.mutations, hasLength(1)); // only the setup edits
          expect(
            module.projection.value.settings!['crosshairColor'],
            '#FFFFFF',
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          module.dispose();
        },
      );
    }

    for (final invalidation in ['owner', 'value', 'disabled', 'removed']) {
      testWidgets(
        '$suite color $invalidation retires owned route without committing stale result',
        (t) async {
          size(t, const Size(900, 900));
          final key = GlobalKey<ColorHarnessState>();
          await t.pumpWidget(ColorHarness(suite, key: key));
          await t.pumpAndSettle();
          await target(t, const Key('overlay-color-open'), 'pointer');
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('overlay-color-hex')),
            '#123456',
          );
          final oldRoute = ModalRoute.of(
            t.element(find.byType(OverlayColorPickerDialog)),
          )!;
          // Invalidate beneath another root dialog: retirement must not pop it.
          final other = showStarBridgeDialog<void>(
            t.element(find.byType(OverlayColorPickerDialog)),
            builder: (_) => const AlertDialog(title: Text('另一个弹窗')),
          );
          await t.pumpAndSettle();
          key.currentState!.change(() {
            switch (invalidation) {
              case 'owner':
                key.currentState!.owner = Object();
              case 'value':
                key.currentState!.value = '#FF0000';
              case 'disabled':
                key.currentState!.enabled = false;
              case 'removed':
                key.currentState!.visible = false;
            }
          });
          await t.pumpAndSettle();
          expect(oldRoute.isActive, isFalse);
          expect(find.text('另一个弹窗'), findsOneWidget);
          expect(key.currentState!.changes, isEmpty);
          dismissStarBridgeDialog<void>(
            t.element(find.text('另一个弹窗')),
            source: InteractionSource.keyboard,
          );
          await t.pumpAndSettle();
          await other;
          expect(find.byType(OverlayColorPickerDialog), findsNothing);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
        },
      );
    }

    testWidgets(
      '$suite open color dialog follows theme and reduction within two frames',
      (t) async {
        size(t, const Size(900, 900));
        final key = GlobalKey<ColorHarnessState>();
        await t.pumpWidget(ColorHarness(suite, key: key));
        await t.pumpAndSettle();
        await target(t, const Key('overlay-color-open'), 'pointer');
        key.currentState!.change(() {
          key.currentState!.reduce = true;
          key.currentState!.light = true;
        });
        await t.pump();
        await t.pump();
        final ctx = t.element(find.byType(OverlayColorPickerDialog));
        expect(InteractionScope.of(ctx).reduceMotion, isTrue);
        expect(Theme.of(ctx).brightness, Brightness.light);
        final route = ModalRoute.of(ctx)! as StarBridgeDialogRoute<String>;
        expect(route.animation!.value, 1);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(key.currentState!.changes, isEmpty);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'choice options shrink/disable/empty without stale menu callbacks',
    (t) async {
      size(t, const Size(360, 700));
      final handle = t.ensureSemantics();
      var options = [
        const StarBridgeSelectOption(value: 'a', label: '选项 A'),
        const StarBridgeSelectOption(value: 'b', label: '选项 B'),
      ];
      String? value = 'a';
      var calls = 0;
      late StateSetter update;
      await t.pumpWidget(
        scopedApp(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return SizedBox(
                width: 220,
                child: StarBridgeSelectField<String>(
                  key: const Key('dynamic-choice'),
                  identity: 'dynamic-choice',
                  value: value,
                  options: options,
                  decoration: const InputDecoration(labelText: '实时选择'),
                  onSelected: (next, _) {
                    calls++;
                    update(() => value = next);
                  },
                ),
              );
            },
          ),
          InteractionSuite.scan,
        ),
      );
      await t.pumpAndSettle();
      await target(t, const Key('dynamic-choice'), 'keyboard');
      update(
        () =>
            options = [const StarBridgeSelectOption(value: 'b', label: '选项 B')],
      );
      await t.pumpAndSettle();
      await choice(t, '选项 B', 'reader');
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(value, 'b');
      await target(t, const Key('dynamic-choice'), 'pointer');
      update(() => options = []);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey(('dynamic-choice', 'b'))), findsNothing);
      expect(calls, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      handle.dispose();
    },
  );

  testWidgets('capture narrow 200% color dialog without clipping', (t) async {
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
                child: const OverlayColorPickerDialog(
                  label: '准星颜色',
                  initialValue: '#45B6E8',
                ),
              ),
            ),
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3U'] != null) {
        await t.runAsync(() async {
          final image =
              await (frame.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            final dir = Directory('build/reviews/interaction-batch3u');
            await dir.create(recursive: true);
            await File('${dir.path}/${suite.name}-color-large.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
    }
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets('capture narrow 200% choice menu within its field width', (
    t,
  ) async {
    size(t, const Size(420, 900));
    final boundary = GlobalKey();
    for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: scopedApp(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: SizedBox(
                  width: 320,
                  child: StarBridgeSelectField<String>(
                    key: const Key('capture-choice'),
                    identity: 'capture-choice',
                    value: 'a',
                    decoration: const InputDecoration(labelText: '外观选择'),
                    options: const [
                      StarBridgeSelectOption(value: 'a', label: '舰队标准'),
                      StarBridgeSelectOption(value: 'b', label: '仅供试装的装饰与配置'),
                    ],
                    onSelected: (_, _) {},
                  ),
                ),
              ),
            ),
            suite,
          ),
        ),
      );
      await t.pumpAndSettle();
      await target(t, const Key('capture-choice'), 'pointer');
      await t.pumpAndSettle();
      final menu = t.getRect(
        find.byKey(const ValueKey<Object>(('capture-choice', 'b'))),
      );
      final anchor = t.getRect(find.byKey(const Key('capture-choice')));
      expect(menu.width, lessThanOrEqualTo(anchor.width));
      expect(menu.left, greaterThanOrEqualTo(8));
      expect(menu.right, lessThanOrEqualTo(412));
      expect(t.takeException(), isNull);
      if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3U'] != null) {
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            final dir = Directory('build/reviews/interaction-batch3u');
            await dir.create(recursive: true);
            await File('${dir.path}/${suite.name}-select-large.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
    }
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
}

extension on Completer<void> {
  void completeIfNeeded() {
    if (!isCompleted) complete();
  }
}
