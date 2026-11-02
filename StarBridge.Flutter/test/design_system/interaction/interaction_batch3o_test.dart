import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:starbridge_flutter/design_system/styles/approved_appearance_thumbnail.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_preset_bar.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_settings_dialog.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_import_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_transfer.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';

import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import '../../features/overlay_settings/overlay_preset_transfer_test.dart'
    show layout;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp, route, dialogAction;
import 'interaction_batch3m_test.dart' show activate, keyPress;
import 'interaction_batch3b_test.dart' show semanticTap;

class Port implements OverlayWorkspacePort {
  Port({this.conflict = false, this.sources = true});
  final bool conflict, sources;
  int revision = 1;
  final writes = <OverlayWorkspaceMutation>[];
  Completer<OverlayWorkspaceWriteResult>? pending;
  OverlaySettingsFailure? failure;
  OverlayWorkspaceSettings? savedSettings;
  List<OverlayWorkspaceLayoutItem>? savedLayout;
  OverlayPresetSources? savedSources;
  OverlayWorkspaceSnapshot get snapshot => OverlayWorkspaceSnapshot.available(
    revision: revision,
    storageState: 'ready',
    activePresetId: 'one',
    renderMode: 'NativeComposition',
    appearances: [],
    hotkey: const OverlayWorkspaceHotkey(
      binding: 'Alt+O',
      enabled: true,
      runtimeState: 'registered',
    ),
    settings: savedSettings ?? settings(),
    layout: savedLayout ?? [],
    sourcePresetsEnabled: sources,
    presets: [
      for (final id in ['one', 'two'])
        OverlayWorkspacePreset(
          id: id,
          name: id == 'one' ? '当前测试预设' : '另一个测试预设',
          isActive: id == 'one',
          storageState: 'ready',
          settings: id == 'one' ? savedSettings ?? settings() : settings(),
          layout: id == 'one' ? savedLayout ?? [] : [],
          sources: !sources
              ? null
              : id == 'one' && savedSources != null
              ? savedSources
              : OverlayPresetSources(
                  binding: const OverlaySourceBinding.room(),
                  autoSwitch: conflict && id == 'two',
                ),
        ),
    ],
  );
  @override
  Future<OverlayWorkspaceSnapshot> read() async => snapshot;
  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    expectSync(expectedRevision, revision);
    writes.add(mutation);
    if (pending != null) return pending!.future;
    if (failure != null) return OverlayWorkspaceWriteResult.failed(failure);
    revision++;
    if (mutation.kind == OverlayWorkspaceMutationKind.saveActive) {
      savedSettings = mutation.settings;
      savedLayout = mutation.layout;
      savedSources = mutation.sources ?? savedSources;
    }
    return OverlayWorkspaceWriteResult.completed(snapshot);
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async => const OverlayRuntimeSnapshot(
    windowState: 'closed',
    isVisible: false,
    appliedRevision: 1,
    hotkeyState: 'registered',
    followGameState: 'manual',
    requestedSkin: 'Default',
    effectiveSkin: 'Default',
    usedFallbackSkin: false,
  );
  @override
  Future<void> close() async {}
}

class Harness extends StatefulWidget {
  const Harness(
    this.module,
    this.suite, {
    this.page = false,
    this.compact = true,
    super.key,
  });
  final OverlayWorkspaceModule module;
  final InteractionSuite suite;
  final bool page, compact;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  bool reduce = false, show = true;
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    !show
        ? const Text('已离开')
        : widget.page
        ? OverlayWorkspacePage(module: widget.module)
        : ValueListenableBuilder<OverlayWorkspaceProjection>(
            valueListenable: widget.module.projection,
            builder: (context, p, _) => OverlayWorkspacePresetBar(
              projection: p,
              module: widget.module,
              compact: widget.compact,
              onImport: () {},
              onExport: () {},
              onOpenAppearance: () {},
            ),
          ),
    widget.suite,
    reduce: reduce,
  );
}

Future<(OverlayWorkspaceModule, HarnessState)> mount(
  WidgetTester t,
  Port port,
  InteractionSuite suite, {
  bool page = false,
  bool compact = true,
  GlobalKey? frame,
}) async {
  size(t, const Size(1280, 1000));
  final module = OverlayWorkspaceModule(port);
  addTearDown(module.dispose);
  await module.refresh();
  final key = GlobalKey<HarnessState>();
  final app = Harness(module, suite, page: page, compact: compact, key: key);
  await t.pumpWidget(
    frame == null ? app : RepaintBoundary(key: frame, child: app),
  );
  if (!compact) {
    // Decode the real asset outside the fake clock; its loading spinner is
    // unrelated to the control animation being tested below.
    await t.pump();
    await t.runAsync(
      () => precacheImage(
        const AssetImage(ApprovedAppearanceThumbnail.assetPath),
        t.element(find.byType(ApprovedAppearanceThumbnail)),
        onError: (error, stack) {}, // Optional artwork is absent in open-core builds.
      ),
    );
  }
  await t.pumpAndSettle();
  return (module, key.currentState!);
}

Future<void> entry(WidgetTester t, String id, String source) async {
  await activate(t, find.byKey(const Key('overlay-preset-manage')), source);
  await t.pumpAndSettle();
  await activate(t, find.byKey(ValueKey<Object>('overlay-preset-$id')), source);
  if (source != 'pointer' && find.byType(AlertDialog).evaluate().isNotEmpty) {
    expect(
      route(t).animation!.value,
      1,
      reason: 'source must reach the next route',
    );
  }
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3O'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3o');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

String package({bool sources = false}) => OverlayPresetTransfer(
  name: '导入测试',
  settings: settings(),
  layout: layout,
  sources: sources ? OverlayPresetSources() : null,
).serialize();

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final outcome in ['success', 'failure', 'disposed']) {
      testWidgets(
        '$suite import $outcome after leaving preserves module authority',
        (t) async {
          final port = Port();
          final (module, state) = await mount(t, port, suite, page: true);
          module.updateSetting('showNotice', false);
          await t.pumpAndSettle();
          port.writes.clear(); // the edit saved on its own
          await entry(t, 'import', 'keyboard');
          await t.enterText(find.byType(TextField).last, package());
          await activate(t, dialogAction('查看导入预览'), 'keyboard');
          await t.pumpAndSettle();
          port.pending = Completer();
          await activate(
            t,
            find.byKey(const Key('overlay-import-confirm')),
            'keyboard',
          );
          // The real page intentionally spins while the Host response is held.
          await t.pump();
          await t.pump(const Duration(milliseconds: 16));
          expect(port.writes, hasLength(1));
          expect(module.projection.value.busy, true);
          state.change(() => state.show = false);
          await t.pumpAndSettle();
          if (outcome == 'disposed') module.dispose();
          port.pending!.complete(
            outcome == 'failure'
                ? const OverlayWorkspaceWriteResult.failed(
                    OverlaySettingsFailure.writeConflict,
                  )
                : OverlayWorkspaceWriteResult.completed(port.snapshot),
          );
          await t.pumpAndSettle();
          expect(find.text('已离开'), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          expect(port.writes, hasLength(1));
          if (outcome != 'disposed') {
            expect(module.projection.value.busy, false);
            expect(module.projection.value.dirty, false);
            expect(module.projection.value.settings!['showNotice'], false);
            expect(
              module.projection.value.failure,
              outcome == 'failure'
                  ? OverlaySettingsFailure.writeConflict
                  : null,
            );
            state.change(() => state.show = true);
            await t.pumpAndSettle();
            expect(module.canUndo, true);
          }
          expect(t.takeException(), isNull);
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source preset naming cancel and delayed commit retain controller through exit',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = Port();
            final (module, _) = await mount(t, port, suite);
            module.updateSetting('showNotice', false);
            await t.pumpAndSettle();
            port.writes.clear(); // the edit saved on its own
            await entry(t, 'copy', source);
            await t.enterText(find.byType(TextField).last, '不提交');
            await activate(t, dialogAction('取消'), source);
            await t.pumpAndSettle();
            expect(port.writes, isEmpty);
            expect(module.projection.value.dirty, isFalse);
            await entry(t, 'rename', source);
            await t.enterText(find.byType(TextField).last, '  新名称  ');
            port.pending = Completer();
            final closing = route(t);
            await activate(t, dialogAction('确定'), source);
            if (source == 'pointer' && suite != InteractionSuite.standard) {
              expect(closing.animation!.value, greaterThan(0));
              expect(
                port.writes,
                isEmpty,
                reason:
                    'must finish route before controller disposal and write',
              );
            }
            await t.pumpAndSettle();
            expect(port.writes.single.name, '新名称');
            expect(
              port.writes.single.kind,
              OverlayWorkspaceMutationKind.renamePreset,
            );
            expect(module.projection.value.busy, isTrue);
            await t.tap(
              find.byKey(const Key('overlay-preset-manage')),
              warnIfMissed: false,
            );
            await t.pump();
            expect(
              find.byKey(const ValueKey<Object>('overlay-preset-copy')),
              findsNothing,
            );
            port.pending!.complete(
              const OverlayWorkspaceWriteResult.failed(
                OverlaySettingsFailure.writeFailed,
              ),
            );
            await t.pumpAndSettle();
            expect(module.projection.value.dirty, isFalse);
            expect(module.projection.value.settings!['showNotice'], false);
            expect(
              module.projection.value.failure,
              OverlaySettingsFailure.writeFailed,
            );
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        '$suite $source actual workspace import inspection is nonmutating until confirm',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = Port();
            final frame = GlobalKey();
            final (module, _) = await mount(
              t,
              port,
              suite,
              page: true,
              frame: frame,
            );
            module.updateSetting('showNotice', false);
            await t.pumpAndSettle();
            port.writes.clear(); // the edit saved on its own
            Future<void> preview() async {
              await entry(t, 'import', source);
              await t.enterText(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(TextField),
                ),
                package(),
              );
              await activate(t, dialogAction('查看导入预览'), source);
              if (source != 'pointer') expect(route(t).animation!.value, 1);
              await t.pumpAndSettle();
              expect(find.byType(OverlayPresetImportPreview), findsOneWidget);
            }

            await preview();
            if (source == 'pointer') {
              await capture(t, frame, '${suite.name}-import');
            }
            expect(port.writes, isEmpty);
            await activate(t, dialogAction('取消'), source);
            await t.pumpAndSettle();
            expect(port.writes, isEmpty);
            await preview();
            await activate(
              t,
              find.byKey(const Key('overlay-import-confirm')),
              source,
            );
            await t.pumpAndSettle();
            expect(
              port.writes.single.kind,
              OverlayWorkspaceMutationKind.importPreset,
            );
            expect(port.writes.single.name, '导入测试');
            expect(module.projection.value.dirty, false);
            expect(module.projection.value.settings!['showNotice'], false);
            expect(module.canUndo, true);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite settings conflict cancel, held save, failure and retry keep edits',
      (t) async {
        final port = Port(conflict: true);
        final frame = GlobalKey();
        final (module, state) = await mount(t, port, suite, frame: frame);
        module.updateSetting('showNotice', false);
        await t.pumpAndSettle();
        port.writes.clear(); // the edit saved on its own
        await activate(
          t,
          find.byKey(const Key('overlay-preset-settings-entry')),
          'keyboard',
        );
        expect(route(t).animation!.value, 1);
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), '配置草稿');
        await t.tap(find.byKey(const Key('overlay-preset-auto-switch')));
        await t.pumpAndSettle();
        await activate(
          t,
          find.byKey(const Key('overlay-preset-settings-save')),
          'keyboard',
        );
        expect(route(t).animation!.value, 1);
        await t.pumpAndSettle();
        await capture(t, frame, '${suite.name}-conflict');
        await activate(t, dialogAction('取消'), 'keyboard');
        await t.pumpAndSettle();
        expect(port.writes, isEmpty);
        expect(find.text('配置草稿'), findsOneWidget);
        await activate(
          t,
          find.byKey(const Key('overlay-preset-settings-save')),
          'pointer',
        );
        await t.pumpAndSettle();
        port.pending = Completer();
        await activate(t, dialogAction('替换并保存'), 'keyboard');
        await t.pumpAndSettle();
        expect(port.writes.single.replaceAutoSwitchPresetId, 'two');
        expect(port.writes.single.sources!.autoSwitch, true);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.byType(OverlayPresetSettingsDialog), findsOneWidget);
        state.change(() => state.reduce = true);
        await t.pump();
        await t.pump();
        port.pending!.complete(
          const OverlayWorkspaceWriteResult.failed(
            OverlaySettingsFailure.writeFailed,
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('overlay-preset-settings-error')),
          findsOneWidget,
        );
        expect(find.text('配置草稿'), findsOneWidget);
        port.pending = null;
        await activate(
          t,
          find.byKey(const Key('overlay-preset-settings-save')),
          'keyboard',
        );
        await t.pumpAndSettle();
        await activate(t, dialogAction('替换并保存'), 'keyboard');
        await t.pumpAndSettle();
        expect(port.writes, hasLength(2));
        expect(find.byType(OverlayPresetSettingsDialog), findsNothing);
        expect(module.projection.value.dirty, false);
        expect(module.projection.value.settings!['showNotice'], false);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite selector switches without asking; live reduce settles routes',
      (t) async {
        final port = Port();
        final (module, state) = await mount(t, port, suite);
        module.updateSetting('showNotice', false);
        await t.pumpAndSettle();
        port.writes.clear(); // the edit saved on its own
        final selector = find.byKey(
          const ValueKey('overlay-preset-selector-one'),
        );
        await keyPress(t, selector);
        await t.pumpAndSettle();
        await keyPress(
          t,
          find.byKey(const ValueKey<Object>('overlay-preset-select-two')),
        );
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          port.writes.single.kind,
          OverlayWorkspaceMutationKind.activatePreset,
        );
        expect(port.writes.single.presetId, 'two');
        expect(module.projection.value.dirty, false);
        await activate(
          t,
          find.byKey(const Key('overlay-preset-manage')),
          'pointer',
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey<Object>('overlay-preset-reset')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 16));
        final opening = route(t);
        state.change(() => state.reduce = true);
        await t.pump();
        await t.pump();
        expect(opening.animation!.value, 1);
        await activate(t, dialogAction('继续'), 'keyboard');
        await t.pumpAndSettle();
        expect(
          port.writes.last.kind,
          OverlayWorkspaceMutationKind.resetPreset,
        );
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite invalid and unsupported import cannot write; leaving before inspect stops flow',
      (t) async {
        final port = Port(sources: false);
        final (_, state) = await mount(t, port, suite, page: true);
        for (final payload in ['not-json', package(sources: true)]) {
          await entry(t, 'import', 'keyboard');
          await t.enterText(find.byType(TextField).last, payload);
          await activate(t, dialogAction('查看导入预览'), 'keyboard');
          await t.pumpAndSettle();
          expect(find.byType(OverlayPresetImportPreview), findsNothing);
          expect(port.writes, isEmpty);
        }
        await entry(t, 'import', 'keyboard');
        await t.enterText(find.byType(TextField).last, package());
        state.change(() => state.show = false);
        await t.pump();
        await activate(t, dialogAction('查看导入预览'), 'keyboard');
        await t.pumpAndSettle();
        expect(find.byType(OverlayPresetImportPreview), findsNothing);
        expect(port.writes, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite noncompact quick rail reader switch needs no confirmation',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          final port = Port();
          final (module, _) = await mount(t, port, suite, compact: false);
          module.updateSetting('showNotice', false);
          await t.pumpAndSettle();
          port.writes.clear(); // the edit saved on its own
          await semanticTap(t, find.bySemanticsLabel(RegExp('^另一个测试预设')).last);
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            port.writes.single.kind,
            OverlayWorkspaceMutationKind.activatePreset,
          );
          expect(module.projection.value.dirty, false);
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
