import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration.dart';

import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_live_session.dart';

import 'overlay_appearance_preview_page_test.dart'
    show Workspace, Window, Preview, installedHajiDescriptor, appearance;

import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_appearance_center.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_preview_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_workspace_adapter.dart';

import 'bridge_overlay_appearance_live_port_test.dart' show Harness;
import 'overlay_appearance_live_session_test.dart' show frame, flush;
import '../friends/social_layout_test.dart' show app, size, loadFonts;

final class EntryPort
    implements
        OverlayWorkspacePort,
        OverlayAppearancePreviewPort,
        OverlayAppearanceLivePort,
        OverlayAppearanceLiveAvailability,
        OverlayAppearanceLiveControlsPort,
        OverlayAppearanceLivePlaybackPort {
  EntryPort({
    required List<OverlayAppearanceConfiguration> configurations,
    this.supported = true,
    List<OverlayWorkspaceAppearance> extraAppearances = const [],
  }) : storage = Workspace(configurations: configurations) {
    if (extraAppearances.isNotEmpty) {
      final s = storage.snapshot;
      storage.snapshot = OverlayWorkspaceSnapshot.available(
        revision: s.revision!,
        storageState: s.storageState!,
        activePresetId: s.activePresetId!,
        renderMode: s.renderMode!,
        appearances: [...s.appearances, ...extraAppearances],
        hotkey: s.hotkey!,
        settings: s.settings!,
        layout: s.layout,
        presets: s.presets,
        sourcePresetsEnabled: s.sourcePresetsEnabled,
        removedOrganizationBindings: s.removedOrganizationBindings,
        appearanceOptionsEnabled: s.appearanceOptionsEnabled,
        appearanceConfigurations: s.appearanceConfigurations,
        appearanceProgressIds: s.appearanceProgressIds,
        appearanceOptions: s.appearanceOptions,
        livePreviewAppearanceIds: s.livePreviewAppearanceIds,
      );
    }
  }
  final Workspace storage;
  final Preview live = Preview();
  final bool supported;
  int oldCarrierOpens = 0;
  @override
  bool get supportsLiveAppearancePreview => supported;
  @override
  Future<OverlayWorkspaceSnapshot> read() => storage.read();
  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) => storage.apply(mutation, expectedRevision: expectedRevision);
  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) => storage.executeRuntime(action, language: language, draft: draft);
  @override
  Future<void> close() async {}
  @override
  Future<String> openAppearancePreview(
    String appearanceId,
    OverlayAppearanceOptions options, {
    bool reduceMotion = false,
  }) async {
    oldCarrierOpens++;
    return 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  }

  @override
  Future<void> closeAppearancePreview(String id) async {}
  @override
  Future<String> openLivePreview(OverlayAppearanceLiveFrame frame) =>
      live.openLivePreview(frame);
  @override
  Future<int> updateLivePreview(
    String id,
    int revision,
    OverlayAppearanceLiveFrame frame,
  ) => live.updateLivePreview(id, revision, frame);
  @override
  Future<void> closeLivePreview(String id) => live.closeLivePreview(id);
  @override
  Future<int> renewLivePreview(String id, int revision) =>
      live.renewLivePreview(id, revision);
  @override
  Future<int> protectLivePreviewControls(
    String id,
    int revision,
    List<OverlayPreviewControlArea> areas,
  ) => live.protectLivePreviewControls(id, revision, areas);
  @override
  Future<bool> playLivePreview(
    String id,
    int revision,
    OverlayAppearancePreviewPlayback action,
  ) => live.playLivePreview(id, revision, action);
}

void main() {
  // Generic entry/save behavior does not require a private installed renderer.
  // An explicit native run additionally uses its exact installed metadata.
  var configurations = <OverlayAppearanceConfiguration>[];
  setUpAll(() async {
    await loadFonts();
    if (Platform.environment['STARBRIDGE_LIVE_PREVIEW_REGRESSION'] != null) {
      configurations = [await installedHajiDescriptor()];
    }
  });
  for (final id in [
    'Default',
    'NightShadow',
    'Verdict',
    'HajiCitizen',
    'FutureCompanion',
    'FutureFreestyle',
  ]) {
    for (final save in [false, true]) {
      testWidgets('$id center opens common page; explicit save=$save', (
        tester,
      ) async {
        size(tester, const Size(1600, 1100));
        final port = EntryPort(
          configurations: configurations,
          extraAppearances: id.startsWith('Future')
              ? [
                  appearance(
                    id,
                    locksTheme: id == 'FutureCompanion',
                    supportsBloom: true,
                  ),
                ]
              : const [],
        );
        final window = Window();
        final module = OverlayWorkspaceModule(port, editorWindow: window);
        await module.initialize();
        final initialRuntimeActions = List.of(port.storage.runtimeActions);
        module.updateSetting('theme', 'Drake');
        final before = module.projection.value;
        expect(before.dirty, isTrue);
        await tester.pumpWidget(
          app(
            TickerMode(
              enabled: false,
              child: Scaffold(
                body: ValueListenableBuilder(
                  valueListenable: module.projection,
                  builder: (_, projection, _) =>
                      OverlayWorkspaceAppearanceCenter(
                        projection: projection,
                        module: module,
                        onBack: () {},
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byKey(Key('overlay-appearance-card-$id'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();
        final entry = find.byKey(Key('overlay-appearance-live-preview-$id'));
        expect(entry, findsOneWidget);
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(OverlayAppearancePreviewPage), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(window.enters, 1);
        expect(port.oldCarrierOpens, 0);
        expect(port.live.opens.single.appearanceId, id);
        expect(
          port.live.opens.single.settings.toMap(),
          before.settings!.toMap(),
        );
        expect(
          port.live.opens.single.layout.map((e) => e.toMap()),
          before.layout.map((e) => e.toMap()),
        );
        // The theme edit saved on its own before the preview opened.
        expect(port.storage.mutations.single.settings!['theme'], 'Drake');
        expect(port.storage.runtimeActions, initialRuntimeActions);
        expect(module.projection.value.settings!['skin'], 'Default');
        if (id.startsWith('Future')) {
          final group = tester
              .widgetList<OverlayWorkspaceSettingsGroup>(
                find.byType(OverlayWorkspaceSettingsGroup),
              )
              .singleWhere((g) => g.group == 'appearance');
          expect(group.settings['skin'], 'Default');
          expect(group.appearanceRule!.locksTheme, id == 'FutureCompanion');
          expect(group.appearanceRule!.supportsBloom, isTrue);
          expect(
            find.byKey(const Key('overlay-field-nightShadowBloom')),
            findsOneWidget,
          );
          expect(
            group.fields.any((f) => f.field == 'theme'),
            id == 'FutureFreestyle',
          );
        }
        if (save) {
          await tester.tap(find.byKey(const Key('appearance-preview-save')));
          await tester.pumpAndSettle();
          // Nothing was pending, so Save writes nothing new.
          expect(port.storage.mutations, hasLength(1));
          expect(port.storage.mutations.single.settings!['skin'], 'Default');
          expect(port.storage.mutations.single.settings!['theme'], 'Drake');
          expect(
            port.storage.mutations.single.layout!.map((e) => e.toMap()),
            before.layout.map((e) => e.toMap()),
          );
          expect(port.live.opens, hasLength(1));
          expect(port.oldCarrierOpens, 0);
          // Save never Opens/Closes/Applies the browsed appearance merely
          // because preview is active.
          expect(port.storage.runtimeActions, initialRuntimeActions);
        }
        await tester.tap(find.byKey(const Key('appearance-preview-exit')));
        await tester.pumpAndSettle();
        expect(window.exits, 1);
        expect(port.live.closes, 1);
        expect(module.projection.value.dirty, isFalse);
        await tester.pumpWidget(const SizedBox());
        module.dispose();
      });
    }
  }
  testWidgets('unsupported new capability never falls back to carrier', (
    tester,
  ) async {
    size(tester, const Size(1600, 1100));
    final port = EntryPort(configurations: configurations, supported: false);
    final module = OverlayWorkspaceModule(port);
    await module.initialize();
    await tester.pumpWidget(
      app(
        TickerMode(
          enabled: false,
          child: Scaffold(
            body: OverlayWorkspaceAppearanceCenter(
              projection: module.projection.value,
              module: module,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-appearance-live-preview-Default')),
      findsNothing,
    );
    expect(port.oldCarrierOpens, 0);
    expect(port.live.opens, isEmpty);
    await tester.pumpWidget(const SizedBox());
    module.dispose();
  });
  test('workspace Adapter preserves finite new preview requests', () async {
    final h = Harness();
    final adapter = BridgeOverlayWorkspaceAdapter(h.session);
    expect(adapter, isA<OverlayAppearanceLivePort>());
    final live = adapter as OverlayAppearanceLivePort;
    final port = EntryPort(configurations: configurations);
    final module = OverlayWorkspaceModule(port);
    await module.initialize();
    final p = module.projection.value;
    final f = OverlayAppearanceLiveFrame(
      appearanceId: 'Default',
      settings: p.settings!,
      layout: p.layout,
      options: p.appearanceOptions,
      language: 'zh-CN',
      reduceMotion: false,
    );
    module.dispose();
    final id = await live.openLivePreview(f);
    await live.updateLivePreview(id, 1, f);
    expect(await live.renewLivePreview(id, 1), 1);
    await (adapter as OverlayAppearanceLiveControlsPort)
        .protectLivePreviewControls(id, 1, [
          const OverlayPreviewControlArea(.8, 0, .2, 1),
        ]);
    await (adapter as OverlayAppearanceLivePlaybackPort).playLivePreview(
      id,
      1,
      OverlayAppearancePreviewPlayback.noticeShow,
    );
    await live.closeLivePreview(id);
    expect(h.requests.map((e) => e.name), [
      'overlay.appearanceLivePreview.open',
      'overlay.appearanceLivePreview.update',
      'overlay.appearanceLivePreview.renew',
      'overlay.appearanceLivePreview.protect',
      'overlay.appearanceLivePreview.playback',
      'overlay.appearanceLivePreview.close',
    ]);
    expect(h.requests.every((e) => e.accountContext == null), isTrue);
    await h.close();
  });
  test(
    'workspace Adapter cannot use old carrier capability as new availability',
    () async {
      final h = Harness(supported: false);
      final adapter = BridgeOverlayWorkspaceAdapter(h.session);
      final module = OverlayWorkspaceModule(adapter);
      expect(adapter.supportsLiveAppearancePreview, isFalse);
      expect(module.appearanceLivePort, isNull);
      await expectLater(adapter.openLivePreview(frame()), throwsStateError);
      expect(h.requests, isEmpty);
      module.dispose();
      await h.close();
    },
  );
  test(
    'workspace Adapter forwards real owner invalidation to common session',
    () async {
      final h = Harness();
      final adapter = BridgeOverlayWorkspaceAdapter(h.session);
      final live = OverlayAppearanceLiveSession(adapter);
      await live.open(frame());
      h.session.advanceGeneration(2);
      await h.ownerEvent();
      await Future<void>.delayed(Duration.zero);
      await flush();
      expect(live.phase, OverlayAppearanceLivePhase.closed);
      expect(h.requests.last.name, 'overlay.appearanceLivePreview.close');
      expect(h.requests.last.sessionGeneration, 2);
      expect(() => live.update(frame()), throwsStateError);
      live.dispose();
      await h.close();
    },
  );
}
