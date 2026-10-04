import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_source_binding_field.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_settings_dialog.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_source_limit_notice.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_preset_bar.dart';

import 'overlay_settings_ux_a_test.dart' show settings;
import '../friends/social_layout_test.dart' show app, size;

void main() {
  for (final width in [1056.0, 1216.0]) {
    testWidgets('preset settings has a direct compact toolbar entry at $width', (tester) async {
      size(tester, Size(width, 900));
      final port = _Port();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      await tester.pumpWidget(app(OverlayWorkspacePresetBar(
        projection: module.projection.value, module: module, compact: true,
        onImport: () {}, onExport: () {}, onOpenAppearance: () {})));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('overlay-preset-settings-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(OverlayPresetSettingsDialog), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(port.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  test('multi-chat v3 preserves draft, undo, runtime payload and preset metadata edits', () async {
    final port = _Port();
    final module = OverlayWorkspaceModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    final sources = [
      const OverlaySourceBinding.room(),
      OverlaySourceBinding.community('org-a', 'owner'),
    ];
    module.updateChatSources(sources);
    expect(module.projection.value.sources!.chatSources, sources);
    expect(module.projection.value.sources!.toMap()['schemaVersion'], 3);
    expect(module.projection.value.dirty, isTrue);
    module.undo();
    expect(module.projection.value.sources!.chatSources, isEmpty);
    module.updateChatSources(sources);
    module.updateModuleSource(
      OverlaySourceModule.notice,
      const OverlaySourceBinding.room(),
    );
    expect(module.projection.value.sources!.chatSources, sources);
    module.discardChanges();
    expect(module.projection.value.sources!.chatSources, isEmpty);
  });
  test('temporary selection preserves unsaved edits and undo without storing the choice', () async {
    final port = _Port();
    final module = OverlayWorkspaceModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    module.updateSetting('crosshairOpacity', 0.37);
    final before = module.projection.value;
    expect(
      await module.selectTemporarySource(
        const OverlaySourceBinding.room(),
        'owner',
      ),
      isTrue,
    );
    final mutation = port.writes.single;
    expect(mutation.kind, OverlayWorkspaceMutationKind.temporarySource);
    expect(mutation.toPayload(1)['ownerKey'], 'owner');
    expect(mutation.runtimeDraft!.settings['crosshairOpacity'], 0.37);
    expect(module.projection.value.dirty, isTrue);
    expect(module.projection.value.settings!['crosshairOpacity'], 0.37);
    expect(module.projection.value.sources, before.sources);
    expect(port.draft!.settings['crosshairOpacity'], 0.37);
    expect(module.canUndo, isTrue);
    module.undo();
    expect(
      module.projection.value.settings!['crosshairOpacity'],
      port.snapshot.settings!['crosshairOpacity'],
    );
  });
  testWidgets(
    'source limit adjustment edits only the draft and does not clear Host warning locally',
    (tester) async {
      size(tester, const Size(800, 900));
      final port = _Port();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      await tester.pumpWidget(app(OverlaySourceLimitNotice(module: module)));
      await tester.pumpAndSettle();
      expect(find.text('来源超限，请调整来源'), findsOneWidget);
      await tester.tap(find.text('调整来源'));
      await tester.pumpAndSettle();
      expect(
        find.byType(DropdownButton<OverlaySourceBinding>),
        findsNWidgets(5),
      );
      await tester.tap(find.byType(DropdownButton<OverlaySourceBinding>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('当前房间').last);
      await tester.pumpAndSettle();
      expect(
        module.projection.value.sources!
            .forModule(OverlaySourceModule.notice)
            .mode,
        OverlaySourceMode.room,
      );
      expect(module.projection.value.dirty, isTrue);
      expect(port.writes, isEmpty);
      await tester.tap(find.text('返回编辑器'));
      await tester.pumpAndSettle();
      expect(find.text('来源超限，请调整来源'), findsOneWidget);
      module.discardChanges();
      expect(
        module.projection.value.sources!
            .forModule(OverlaySourceModule.notice)
            .mode,
        OverlaySourceMode.none,
      );
    },
  );
  testWidgets('automatic source replacement needs explicit confirmation', (
    tester,
  ) async {
    size(tester, const Size(800, 900));
    final port = _Port(conflict: true);
    final module = OverlayWorkspaceModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await tester.pumpWidget(
      app(
        OverlayPresetSettingsDialog(
          module: module,
          preset: port.snapshot.presets.first,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<OverlaySourceBinding>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('当前房间').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overlay-preset-settings-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Room preset'), findsOneWidget);
    expect(port.writes, isEmpty);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(port.writes, isEmpty);
    await tester.tap(find.byKey(const Key('overlay-preset-settings-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('替换并保存'));
    await tester.pumpAndSettle();
    expect(port.writes.single.replaceAutoSwitchPresetId, 'existing-room');
    expect(port.writes.single.sources!.autoSwitch, isTrue);
  });
  testWidgets('settings reject a workspace changed after opening the dialog', (
    tester,
  ) async {
    size(tester, const Size(800, 900));
    final port = _Port();
    final module = OverlayWorkspaceModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => OverlayPresetSettingsDialog(
                module: module,
                preset: port.snapshot.presets.single,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await module.configurePreset(
      'fixture',
      'Changed elsewhere',
      const OverlaySourceBinding.room(),
      false,
    );
    port.writes.clear();
    await tester.tap(find.byKey(const Key('overlay-preset-settings-save')));
    await tester.pumpAndSettle();
    expect(port.writes, isEmpty);
    expect(
      find.byKey(const Key('overlay-preset-settings-error')),
      findsOneWidget,
    );
  });
  test(
    'preset metadata save rebases undo history without saving the module draft',
    () async {
      final port = _Port();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      module.updateModuleSource(
        OverlaySourceModule.chat,
        const OverlaySourceBinding.room(),
      );
      expect(
        await module.configurePreset(
          'fixture',
          'Room preset',
          const OverlaySourceBinding.room(),
          true,
          expectedRevision: 1,
        ),
        isTrue,
      );
      expect(
        port.writes.single.sources!.forModule(OverlaySourceModule.chat).mode,
        OverlaySourceMode.none,
      );
      expect(
        module.projection.value.sources!
            .forModule(OverlaySourceModule.chat)
            .mode,
        OverlaySourceMode.room,
      );
      expect(
        module.projection.value.sources!.binding.mode,
        OverlaySourceMode.room,
      );
      expect(module.projection.value.dirty, isTrue);
      module.undo();
      expect(
        module.projection.value.sources!.binding.mode,
        OverlaySourceMode.room,
      );
      expect(module.projection.value.sources!.autoSwitch, isTrue);
      expect(
        module.projection.value.sources!
            .forModule(OverlaySourceModule.chat)
            .mode,
        OverlaySourceMode.none,
      );
      expect(module.projection.value.dirty, isFalse);
      module.redo();
      expect(
        module.projection.value.sources!
            .forModule(OverlaySourceModule.chat)
            .mode,
        OverlaySourceMode.room,
      );
      expect(
        await module.configurePreset(
          'fixture',
          'Stale',
          const OverlaySourceBinding.follow(),
          false,
          expectedRevision: 1,
        ),
        isFalse,
      );
      expect(port.writes, hasLength(1));
    },
  );

  testWidgets('preset settings cancel writes nothing and save is explicit', (
    tester,
  ) async {
    size(tester, const Size(800, 900));
    final port = _Port();
    final module = OverlayWorkspaceModule(port);
    addTearDown(module.dispose);
    await module.refresh();
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => OverlayPresetSettingsDialog(
                module: module,
                preset: port.snapshot.presets.single,
              ),
            ),
            child: const Text('Open settings'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsOneWidget);
    final automatic = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(automatic.value, isFalse);
    expect(automatic.onChanged, isNull);
    expect(find.textContaining('先将信息来源设为当前房间'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<OverlaySourceBinding>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('当前房间').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(port.writes, isEmpty);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.tap(find.byKey(const Key('overlay-preset-settings-save')));
    await tester.pumpAndSettle();
    expect(port.writes.single.name, 'Renamed');
    expect(find.byType(OverlayPresetSettingsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'source field remains actionable and keeps unavailable bindings without exposing their identity',
    (tester) async {
      size(tester, const Size(600, 500));
      final original = OverlaySourceBinding.community(
        'private-code',
        'different-owner',
      );
      OverlaySourceBinding? selected;
      await tester.pumpWidget(
        app(
          Center(
            child: SizedBox(
              width: 300,
              child: OverlaySourceBindingField(
                value: original,
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('所选组织暂不可用'), findsOneWidget);
      expect(find.textContaining('private-code'), findsNothing);
      expect(find.textContaining('different-owner'), findsNothing);
      expect(selected, isNull);
      await tester.tap(find.byType(DropdownButton<OverlaySourceBinding>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('当前房间').last);
      await tester.pumpAndSettle();
      expect(selected, const OverlaySourceBinding.room());
      expect(tester.takeException(), isNull);
    },
  );
  test('source policy matches Host v2 shape and is immutable', () {
    final mutable = <OverlaySourceModule, OverlaySourceBinding>{
      OverlaySourceModule.members: const OverlaySourceBinding.room(),
    };
    final value = OverlayPresetSources(
      binding: OverlaySourceBinding.community('org', 'owner'),
      modules: mutable,
    );
    mutable.clear();
    expect(
      value.forModule(OverlaySourceModule.members).mode,
      OverlaySourceMode.room,
    );
    final json = jsonDecode(jsonEncode(value.toMap())) as Map<String, dynamic>;
    expect(json['schemaVersion'], 2);
    expect((json['moduleSources'] as Map).keys.toSet(), {
      'notice',
      'overview',
      'members',
      'chat',
      'events',
    });
    expect(OverlayPresetSources.fromMap(json), value);
    expect(value.autoSwitch, isFalse);
    expect(() => value.modules.clear(), throwsUnsupportedError);
    expect(() => OverlayPresetSources(autoSwitch: true), throwsFormatException);
    for (final bad in [
      {...json, 'schemaVersion': 3},
      {...json, 'authority': true},
      {...json, 'moduleSources': <String, Object?>{}},
      {
        ...json,
        'sourceBinding': {
          'mode': 'room',
          'communityCode': 'org',
          'ownerKey': 'owner',
        },
      },
      {
        ...json,
        'sourceBinding': {
          'mode': 'community',
          'communityCode': ' org',
          'ownerKey': 'owner',
        },
      },
      {
        ...json,
        'sourceBinding': {
          'mode': 'local',
          'communityCode': null,
          'ownerKey': null,
        },
      },
    ]) {
      expect(() => OverlayPresetSources.fromMap(bad), throwsFormatException);
    }
  });

  test(
    'sources follow undo, redo, discard and explicit save without lost draft',
    () async {
      final port = _Port();
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      final original = module.projection.value.sources;
      module.updateModuleSource(
        OverlaySourceModule.members,
        const OverlaySourceBinding.room(),
      );
      expect(module.projection.value.dirty, isTrue);
      expect(port.writes, isEmpty);
      expect(
        module.projection.value.sources!
            .forModule(OverlaySourceModule.members)
            .mode,
        OverlaySourceMode.room,
      );
      module.undo();
      expect(module.projection.value.sources, original);
      expect(module.projection.value.dirty, isFalse);
      module.redo();
      await module.openRuntime('en');
      expect(port.draft?.sources, module.projection.value.sources);
      expect(port.writes, isEmpty);
      await module.renamePreset('fixture', 'renamed');
      expect(
        module.projection.value.sources!
            .forModule(OverlaySourceModule.members)
            .mode,
        OverlaySourceMode.room,
      );
      expect(module.projection.value.dirty, isTrue);
      await module.save();
      expect(
        port.writes.last.sources!.forModule(OverlaySourceModule.members).mode,
        OverlaySourceMode.room,
      );
      expect(port.writes.last.toPayload(1)['sources'], isA<Map>());
      module.updateModuleSource(
        OverlaySourceModule.chat,
        const OverlaySourceBinding.room(),
      );
      module.discardChanges();
      expect(module.projection.value.sources, original);
      expect(module.projection.value.dirty, isFalse);
    },
  );

  test(
    'legacy gate keeps source edits inert and source fields absent from drafts',
    () async {
      final port = _Port(enabled: false);
      final module = OverlayWorkspaceModule(port);
      addTearDown(module.dispose);
      await module.refresh();
      module.updateModuleSource(
        OverlaySourceModule.members,
        const OverlaySourceBinding.room(),
      );
      expect(module.projection.value.dirty, isFalse);
      await module.openRuntime('en');
      expect(port.draft?.toMap().containsKey('sources'), isFalse);
      expect(port.writes, isEmpty);
    },
  );
}

final class _Port implements OverlayWorkspacePort {
  _Port({bool enabled = true, bool conflict = false})
    : snapshot = OverlayWorkspaceSnapshot.available(
        revision: 1,
        storageState: 'ready',
        activePresetId: 'fixture',
        renderMode: 'NativeComposition',
        appearances: [],
        hotkey: const OverlayWorkspaceHotkey(
          binding: 'Alt+O',
          enabled: true,
          runtimeState: 'registered',
        ),
        settings: settings(),
        layout: [],
        sourcePresetsEnabled: enabled,
        presets: [
          OverlayWorkspacePreset(
            id: 'fixture',
            name: 'Fixture',
            isActive: true,
            storageState: 'ready',
            settings: settings(),
            layout: [],
            sources: enabled ? OverlayPresetSources() : null,
          ),
          if (conflict)
            OverlayWorkspacePreset(
              id: 'existing-room',
              name: 'Room preset',
              isActive: false,
              storageState: 'ready',
              settings: settings(),
              layout: [],
              sources: OverlayPresetSources(
                binding: const OverlaySourceBinding.room(),
                autoSwitch: true,
              ),
            ),
        ],
      );
  OverlayWorkspaceSnapshot snapshot;
  final writes = <OverlayWorkspaceMutation>[];
  OverlayWorkspaceRuntimeDraft? draft;
  @override
  Future<OverlayWorkspaceSnapshot> read() async => snapshot;
  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    writes.add(mutation);
    if (mutation.kind == OverlayWorkspaceMutationKind.configurePresetSources) {
      snapshot = OverlayWorkspaceSnapshot.available(
        revision: snapshot.revision! + 1,
        storageState: 'ready',
        activePresetId: snapshot.activePresetId!,
        renderMode: snapshot.renderMode!,
        appearances: snapshot.appearances,
        hotkey: snapshot.hotkey!,
        settings: snapshot.settings!,
        layout: snapshot.layout,
        sourcePresetsEnabled: true,
        presets: [
          for (final preset in snapshot.presets)
            OverlayWorkspacePreset(
              id: preset.id,
              name: preset.id == mutation.presetId
                  ? mutation.name ?? preset.name
                  : preset.name,
              isActive: preset.isActive,
              storageState: preset.storageState,
              settings: preset.settings,
              layout: preset.layout,
              sources: preset.id == mutation.presetId
                  ? mutation.sources
                  : preset.id == mutation.replaceAutoSwitchPresetId
                  ? OverlayPresetSources(
                      binding: preset.sources!.binding,
                      modules: preset.sources!.modules,
                    )
                  : preset.sources,
            ),
        ],
      );
    }
    return OverlayWorkspaceWriteResult.completed(snapshot);
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async {
    this.draft = draft;
    return const OverlayRuntimeSnapshot(
      windowState: 'closed',
      isVisible: false,
      appliedRevision: 1,
      hotkeyState: 'registered',
      followGameState: 'manual',
      requestedSkin: 'Default',
      effectiveSkin: 'Default',
      usedFallbackSkin: false,
    );
  }

  @override
  Future<void> close() async {}
}
