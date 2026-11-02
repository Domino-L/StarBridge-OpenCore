import 'dart:io';
import 'dart:ui' show Tristate, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_appearance_center.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration_panel.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_collection_panel.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_options.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_live_session.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_preview_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_preview_playback_controls.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/overlay_settings/overlay_appearance_center_entry_test.dart'
    show EntryPort;
import '../../features/overlay_settings/overlay_appearance_preview_page_test.dart'
    show Window;
import '../../features/overlay_settings/overlay_appearance_live_session_test.dart'
    show settings;
import '../../features/overlay_settings/overlay_appearance_configuration_test.dart'
    as config;
import '../../features/overlay_settings/overlay_appearance_progress_test.dart'
    as progress;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3m_test.dart' show activate;
import 'interaction_batch3b_test.dart' show semanticTap;

// Run the real Module and native-preview session, not a copied lab callback.
// The finite ports do not claim installed renderer or Windows device acceptance.
Future<void> target(WidgetTester t, Key key, String source) async {
  final finder = find.byKey(key);
  await t.ensureVisible(finder);
  if (source == 'reader') {
    await semanticTap(t, finder);
  } else if (source == 'keyboard') {
    final widget = t.widget(finder);
    final native = find.descendant(
      of: finder,
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    final detector = find.descendant(
      of: finder,
      matching: find.byType(FocusableActionDetector),
    );
    final FocusNode focus;
    if (widget is ButtonStyleButton) {
      focus = widget.focusNode!;
    } else if (detector.evaluate().isNotEmpty) {
      focus = t.widget<FocusableActionDetector>(detector.first).focusNode!;
    } else {
      expect(native, findsOneWidget);
      focus = t.widget<ButtonStyleButton>(native).focusNode!;
    }
    expect(focus.canRequestFocus, isTrue);
    focus.requestFocus();
    await t.pump();
    expect(FocusManager.instance.primaryFocus, same(focus));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await t.tap(finder);
  }
  await t.pump();
  await t.pump();
}

Future<void> icon(WidgetTester t, Key key, String source) async {
  final adapter = find.byWidgetPredicate(
    (w) => w is StarBridgeIconAction && w.controlKey == key,
  );
  final widget = t.widget<StarBridgeIconAction>(adapter);
  if (source == 'reader') {
    await semanticTap(t, find.byKey(key));
  } else if (source == 'keyboard') {
    Focus.of(t.element(find.byWidget(widget.icon))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await t.tap(find.byKey(key));
  }
  await t.pump();
  await t.pump();
}

StarBridgeActionButton button(WidgetTester t, String key) =>
    t.widget<StarBridgeActionButton>(find.byKey(Key(key)));

class PreviewHarness extends StatefulWidget {
  const PreviewHarness(this.module, this.port, this.suite, {super.key});
  final OverlayWorkspaceModule module;
  final EntryPort port;
  final InteractionSuite suite;
  @override
  State<PreviewHarness> createState() => PreviewHarnessState();
}

class PreviewHarnessState extends State<PreviewHarness> {
  bool reduce = false;
  void reduced() => setState(() => reduce = true);
  @override
  Widget build(BuildContext context) => scopedApp(
    Builder(
      builder: (context) => StarBridgeActionButton(
        key: const Key('open-preview'),
        onActivate: (_) => showOverlayAppearancePreviewPage(
          context,
          module: widget.module,
          port: widget.port,
          appearanceId: 'Verdict',
        ),
        child: const Text('打开预览'),
      ),
    ),
    widget.suite,
    reduce: reduce,
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source catalog selection preserves locked qualification and back',
        (t) async {
          size(t, const Size(1600, 1100));
          final handle = t.ensureSemantics();
          final port = EntryPort(configurations: []);
          final module = OverlayWorkspaceModule(port);
          await module.initialize();
          var backs = 0;
          try {
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder(
                  valueListenable: module.projection,
                  builder: (_, p, _) => OverlayWorkspaceAppearanceCenter(
                    projection: p,
                    module: module,
                    onBack: () => backs++,
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            const key = Key('overlay-appearance-card-NightShadow');
            await target(t, key, source);
            await t.pumpAndSettle();
            expect(
              t
                  .getSemantics(find.byKey(key))
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected,
              Tristate.isTrue,
            );
            expect(
              button(t, 'overlay-appearance-apply-NightShadow').onActivate,
              isNull,
            );
            expect(module.projection.value.settings!['skin'], 'Default');
            expect(port.storage.mutations, isEmpty);
            await icon(t, const Key('overlay-appearance-center-back'), source);
            expect(backs, 1);
            expect(port.storage.mutations, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            module.dispose();
            handle.dispose();
          }
        },
      );

      testWidgets(
        '$suite $source preview protects controls; guide move collapse close retain owner',
        (t) async {
          size(t, const Size(1280, 900));
          final handle = t.ensureSemantics();
          final port = EntryPort(configurations: []);
          final window = Window();
          final module = OverlayWorkspaceModule(port, editorWindow: window);
          await module.initialize();
          final before = module.projection.value.settings!.toMap();
          try {
            await t.pumpWidget(PreviewHarness(module, port, suite));
            await t.pumpAndSettle();
            await activate(t, find.byKey(const Key('open-preview')), source);
            await t.pumpAndSettle();
            expect(find.byType(OverlayAppearancePreviewPage), findsOneWidget);
            expect(window.enters, 1);
            expect(port.live.opens, hasLength(1));
            expect(port.live.protections, isNotEmpty);
            final route = ModalRoute.of(
              t.element(find.byType(OverlayAppearancePreviewPage)),
            )!;
            expect(route.transitionDuration, Duration.zero);
            final beforeHelp = port.live.protections.length;
            await icon(t, const Key('appearance-preview-help'), source);
            await t.pumpAndSettle();
            expect(port.live.protections.length, greaterThan(beforeHelp));
            expect(
              find.byKey(const Key('appearance-preview-guide')),
              findsOneWidget,
            );
            await activate(
              t,
              find.byKey(const Key('appearance-preview-guide-confirm')),
              source,
            );
            await t.pumpAndSettle();
            expect(
              find.byKey(const Key('appearance-preview-guide')),
              findsNothing,
            );
            final protections = port.live.protections.length;
            await icon(t, const Key('appearance-preview-switch-side'), source);
            await t.pumpAndSettle();
            expect(port.live.protections.length, greaterThan(protections));
            await icon(t, const Key('appearance-preview-collapse'), source);
            await t.pumpAndSettle();
            await icon(t, const Key('appearance-preview-collapse'), source);
            await t.pumpAndSettle();
            expect(module.projection.value.settings!.toMap(), before);
            expect(port.storage.mutations, isEmpty);
            module.updateSetting('theme', 'Drake');
            await t.pumpAndSettle();
            // Saved on its own; the preview's save action only lights up for
            // an edit that failed to save.
            expect(
              t
                  .widget<StarBridgeIconAction>(
                    find.byWidgetPredicate(
                      (w) =>
                          w is StarBridgeIconAction &&
                          w.controlKey == const Key('appearance-preview-save'),
                    ),
                  )
                  .onActivate,
              isNull,
            );
            expect(port.storage.mutations, hasLength(1));
            expect(port.storage.mutations.single.settings!['theme'], 'Drake');
            expect(module.projection.value.settings!['skin'], 'Default');
            await icon(t, const Key('appearance-preview-exit'), source);
            await t.pumpAndSettle();
            expect(port.live.closes, 1);
            expect(window.exits, 1);
            expect(find.byType(OverlayAppearancePreviewPage), findsNothing);
            expect(port.storage.mutations, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            module.dispose();
            handle.dispose();
          }
        },
      );

      testWidgets(
        '$suite $source clear preserves other profiles; refresh failed pending late owner',
        (t) async {
          size(t, const Size(1100, 900));
          final handle = t.ensureSemantics();
          final descriptor = OverlayAppearanceConfiguration.fromMap(
            config.withGlobalField(),
          );
          var options = descriptor.changeField(
            const OverlayAppearanceOptions.empty(),
            'backdrop',
            true,
          );
          options = descriptor.select(options, 'slot0', 1);
          options = options.withProfile('other', {
            'version': 1,
            'values': {'keep': true},
          });
          final port = progress.Port();
          var changes = 0;
          late StateSetter update;
          try {
            await t.pumpWidget(
              scopedApp(
                SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (_, setState) {
                      update = setState;
                      return Column(
                        children: [
                          OverlayAppearanceConfigurationPanel(
                            configuration: descriptor,
                            options: options,
                            onChanged: (value) => update(() {
                              options = value;
                              changes++;
                            }),
                          ),
                          OverlayAppearanceCollectionPanel(
                            appearanceId: 'Fixture',
                            port: port,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await activate(
              t,
              find.byKey(const Key('appearance-config-clear-fixture')),
              source,
            );
            await t.pumpAndSettle();
            expect(changes, 1);
            expect(
              descriptor.read(options)!.values.every((r) => r == null),
              isTrue,
            );
            expect(descriptor.readFields(options), {'backdrop': true});
            expect(options.profile('other')!['values'], {'keep': true});
            expect(
              button(t, 'appearance-config-clear-fixture').onActivate,
              isNull,
            );
            port.fail = true;
            await activate(
              t,
              find.byKey(const Key('appearance-collection-refresh')),
              source,
            );
            await t.pumpAndSettle();
            expect(find.text('未能读取收藏，请刷新重试。'), findsOneWidget);
            port.fail = false;
            port.hold = true;
            await activate(
              t,
              find.byKey(const Key('appearance-collection-refresh')),
              source,
            );
            expect(
              button(t, 'appearance-collection-refresh').onActivate,
              isNull,
            );
            expect(port.pending, hasLength(1));
            final stale = port.pending.single;
            port.owner.add(null);
            await t.pump();
            await t.pump();
            expect(port.pending, hasLength(2));
            port.pending.last.complete(
              progress.parse(progress.receipt(state: 'authenticationRequired')),
            );
            await t.pumpAndSettle();
            stale.complete(progress.parse(progress.receipt(total: 60000)));
            await t.pumpAndSettle();
            expect(find.text('登录已失效，请重新登录'), findsOneWidget);
            expect(find.text('已同步'), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            await port.owner.close();
            handle.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite app reduced motion updates live frame without changing saved settings',
      (t) async {
        size(t, const Size(1280, 900));
        final port = EntryPort(configurations: []);
        final module = OverlayWorkspaceModule(port, editorWindow: Window());
        await module.initialize();
        module.updateSetting('animationFrameRate', 'Fps60');
        final before = module.projection.value.settings!.toMap();
        final key = GlobalKey<PreviewHarnessState>();
        await t.pumpWidget(PreviewHarness(module, port, suite, key: key));
        await t.pumpAndSettle();
        await activate(t, find.byKey(const Key('open-preview')), 'pointer');
        await t.pumpAndSettle();
        expect(port.live.opens.single.reduceMotion, isFalse);
        key.currentState!.reduced();
        await t.pump();
        await t.pump();
        await t.pumpAndSettle();
        expect(port.live.updates.last.reduceMotion, isTrue);
        expect(
          t
              .widget<StarBridgeCheckboxTile>(
                find.byKey(const Key('appearance-preview-reduced-motion')),
              )
              .onChanged,
          isNull,
        );
        expect(module.projection.value.settings!.toMap(), before);
        expect(
          port.storage.mutations,
          hasLength(1),
          reason: 'only the frame-rate edit itself was saved',
        );
        await icon(t, const Key('appearance-preview-exit'), 'pointer');
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        module.dispose();
      },
    );

    testWidgets(
      '$suite finite playback callbacks and reduced/read-only guards',
      (t) async {
        size(t, const Size(1100, 900));
        final plays = <OverlayAppearancePreviewPlayback>[];
        var editable = true, reduced = false;
        late StateSetter update;
        await t.pumpWidget(
          scopedApp(
            StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return OverlayAppearancePreviewPlaybackControls(
                  settings: settings(),
                  editable: editable,
                  reduced: reduced,
                  onPlay: (action) async => plays.add(action),
                  onReducedMotion: (value) => update(() => reduced = value),
                );
              },
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        for (final source in ['pointer', 'keyboard', 'reader']) {
          final handle = t.ensureSemantics();
          await activate(
            t,
            find.byKey(const Key('appearance-preview-play-stop')),
            source,
          );
          handle.dispose();
        }
        expect(plays, List.filled(3, OverlayAppearancePreviewPlayback.stop));
        update(() => reduced = true);
        await t.pumpAndSettle();
        expect(
          button(t, 'appearance-preview-play-transition').onActivate,
          isNull,
        );
        expect(
          button(t, 'appearance-preview-play-eventSequence').onActivate,
          isNull,
        );
        expect(button(t, 'appearance-preview-play-stop').onActivate, isNotNull);
        update(() => editable = false);
        await t.pumpAndSettle();
        expect(button(t, 'appearance-preview-play-stop').onActivate, isNull);
        expect(plays, hasLength(3));
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
  }

  testWidgets('capture approved catalog and preview toolbar at enlarged text', (
    t,
  ) async {
    size(t, const Size(1600, 1100));
    final port = EntryPort(configurations: []);
    final module = OverlayWorkspaceModule(port);
    await module.initialize();
    final boundary = GlobalKey();
    for (final sample in [
      (InteractionSuite.scan, false),
      (InteractionSuite.glow, false),
      (InteractionSuite.scan, true),
      (InteractionSuite.glow, true),
    ]) {
      final suite = sample.$1, preview = sample.$2;
      await t.pumpWidget(
        scopedApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: RepaintBoundary(
                key: boundary,
                child: preview
                    ? OverlayAppearancePreviewPage(
                        module: module,
                        port: port,
                        appearanceId: 'Verdict',
                      )
                    : OverlayWorkspaceAppearanceCenter(
                        projection: module.projection.value,
                        module: module,
                        onBack: () {},
                      ),
              ),
            ),
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3T'] != null) {
        await t.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final bitmap = await render.toImage();
          final bytes = await bitmap.toByteData(format: ImageByteFormat.png);
          final dir = Directory('build/reviews/interaction-batch3t');
          await dir.create(recursive: true);
          await File(
            '${dir.path}/${suite.name}-${preview ? 'preview' : 'catalog'}-large.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          bitmap.dispose();
        });
      }
    }
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    module.dispose();
  });
}
