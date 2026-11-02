import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preview_guide_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_configuration.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_module.dart';

import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';

import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_flutter/platform/window/overlay_editor_window_port.dart';

import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_live_session.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_preview_page.dart';

import 'overlay_appearance_live_session_test.dart' show settings, fullLayout;
import 'overlay_saved_snapshot.dart';

import 'package:starbridge_flutter/features/overlay_settings/overlay_color_picker.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts;

// Use actual workspace Module/projection/save semantics with a finite storage
// fixture. Native renderer/regions are covered separately in the native suite.
OverlayWorkspaceAppearance appearance(
  String id, {
  bool? locksTheme,
  bool? supportsBloom,
}) => OverlayWorkspaceAppearance(
  id: id,
  displayNameZh:
      const {
        'Default': '舰队标准',
        'NightShadow': '夜影',
        'Verdict': '裁决',
        'HajiCitizen': '哈基公民',
      }[id] ??
      id,
  displayNameEn: id,
  summaryZh: 'fixture',
  summaryEn: 'fixture',
  traitsZh: ['fixture'],
  traitsEn: ['fixture'],
  previewSurface: '#102020',
  previewPrimary: '#5599AA',
  previewSecondary: '#FFFFFF',
  locksTheme: locksTheme ?? id != 'Default',
  supportsBloom: supportsBloom ?? (id == 'NightShadow' || id == 'Verdict'),
  startupTransition: 'None',
  requiresEntitlement: id != 'Default',
  isReleased: id != 'HajiCitizen',
  isAvailable: id == 'Default',
  isPreviewAvailable: true,
);

final class Workspace implements OverlayWorkspacePort, OverlayPreviewGuidePort {
  bool guideSeen = true, guideReadFails = false, guideWriteFails = false;
  int guideWrites = 0;
  Completer<bool>? guideRead;
  @override
  Future<bool> readPreviewGuideSeen() async {
    if (guideReadFails) throw StateError('read failed');
    return await guideRead?.future ?? guideSeen;
  }

  @override
  Future<void> markPreviewGuideSeen() async {
    guideWrites++;
    if (guideWriteFails) throw StateError('write failed');
    guideSeen = true;
  }

  Workspace({List<OverlayAppearanceConfiguration> configurations = const []}) {
    final s = settings();
    snapshot = OverlayWorkspaceSnapshot.available(
      revision: 1,
      storageState: 'ready',
      activePresetId: 'fixture',
      renderMode: 'DirectComposition',
      appearances: [
        for (final id in ['Default', 'NightShadow', 'Verdict', 'HajiCitizen'])
          appearance(id),
      ],
      hotkey: const OverlayWorkspaceHotkey(
        binding: 'Alt+O',
        enabled: false,
        runtimeState: 'unavailable',
      ),
      settings: s,
      layout: fullLayout(),
      presets: [
        OverlayWorkspacePreset(
          id: 'fixture',
          name: 'fixture',
          isActive: true,
          storageState: 'ready',
          settings: s,
          layout: fullLayout(),
        ),
      ],
      appearanceOptionsEnabled: true,
      appearanceConfigurations: configurations,
    );
  }
  late OverlayWorkspaceSnapshot snapshot;
  final mutations = <OverlayWorkspaceMutation>[];
  OverlaySettingsFailure? writeFailure;
  final runtimeActions = <OverlayRuntimeAction>[];
  @override
  Future<OverlayWorkspaceSnapshot> read() async => snapshot;
  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    mutations.add(mutation);
    if (writeFailure case final failure?) {
      return OverlayWorkspaceWriteResult.failed(failure);
    }
    if (mutation.kind == OverlayWorkspaceMutationKind.saveActive) {
      snapshot = savedOverlaySnapshot(snapshot, mutation);
    }
    return OverlayWorkspaceWriteResult.completed(snapshot);
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async {
    runtimeActions.add(action);
    return const OverlayRuntimeSnapshot(
      windowState: 'closed',
      isVisible: false,
      appliedRevision: 1,
      hotkeyState: 'unavailable',
      followGameState: 'waitingForGame',
      requestedSkin: 'Default',
      effectiveSkin: 'Default',
      usedFallbackSkin: false,
    );
  }

  @override
  Future<void> close() async {}
}

final class Window implements OverlayEditorWindowPort {
  int enters = 0, exits = 0;
  @override
  Future<void> enter() async {
    enters++;
  }

  @override
  Future<void> exit() async {
    exits++;
  }
}

final class Preview
    implements
        OverlayAppearanceLivePort,
        OverlayAppearanceLiveControlsPort,
        OverlayAppearanceLivePlaybackPort {
  final opens = <OverlayAppearanceLiveFrame>[];
  final updates = <OverlayAppearanceLiveFrame>[];
  final protections = <List<OverlayPreviewControlArea>>[];
  int closes = 0;
  final renewals = <int>[];
  @override
  Future<int> renewLivePreview(String id, int revision) async {
    renewals.add(revision);
    return revision;
  }

  Completer<String>? opening;
  Completer<int>? protection;
  final plays = <OverlayAppearancePreviewPlayback>[];
  @override
  Future<bool> playLivePreview(
    String id,
    int revision,
    OverlayAppearancePreviewPlayback action,
  ) async {
    plays.add(action);
    return true;
  }

  @override
  Future<String> openLivePreview(OverlayAppearanceLiveFrame frame) async {
    opens.add(frame);
    return await opening?.future ?? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  }

  @override
  Future<int> updateLivePreview(
    String id,
    int revision,
    OverlayAppearanceLiveFrame frame,
  ) async {
    updates.add(frame);
    return revision;
  }

  @override
  Future<void> closeLivePreview(String id) async {
    closes++;
  }

  @override
  Future<int> protectLivePreviewControls(
    String id,
    int revision,
    List<OverlayPreviewControlArea> areas,
  ) async {
    protections.add(areas);
    return await protection?.future ?? revision;
  }
}

Future<OverlayAppearanceConfiguration> installedHajiDescriptor() async {
  final assembly = Platform.environment['STARBRIDGE_LIVE_PREVIEW_REGRESSION'];
  if (assembly == null) {
    throw StateError('Set STARBRIDGE_LIVE_PREVIEW_REGRESSION.');
  }
  final result = await Process.run('dotnet', [assembly, '--describe-haji']);
  expect(result.exitCode, 0);
  return OverlayAppearanceConfiguration.fromMap(
    jsonDecode(result.stdout as String) as Map<String, Object?>,
  );
}

void main() {
  testWidgets(
    'guide waits for native protection before display and acknowledgement',
    (tester) async {
      size(tester, const Size(1280, 900));
      final storage = Workspace()..guideRead = Completer<bool>();
      final port = Preview();
      final module = OverlayWorkspaceModule(storage);
      await module.initialize();
      await tester.pumpWidget(
        app(
          OverlayAppearancePreviewPage(
            module: module,
            port: port,
            appearanceId: 'Default',
          ),
        ),
      );
      await tester.pumpAndSettle();
      port.protection = Completer<int>();
      storage.guideRead!.complete(false);
      await tester.pump();
      expect(find.byKey(const Key('appearance-preview-guide')), findsNothing);
      expect(storage.guideWrites, 0);
      port.protection!.complete(2);
      port.protection = null;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appearance-preview-guide')), findsOneWidget);
      expect(storage.guideWrites, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      module.dispose();
    },
  );
  for (final readFailure in [true, false]) {
    testWidgets(
      'guide preference failure leaves preview usable read=$readFailure',
      (tester) async {
        size(tester, const Size(1280, 900));
        final storage = Workspace()
          ..guideSeen = false
          ..guideReadFails = readFailure
          ..guideWriteFails = !readFailure;
        final port = Preview();
        final module = OverlayWorkspaceModule(storage);
        await module.initialize();
        await tester.pumpWidget(
          app(
            OverlayAppearancePreviewPage(
              module: module,
              port: port,
              appearanceId: 'HajiCitizen',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(storage.guideSeen, false);
        expect(storage.guideWrites, readFailure ? 0 : 1);
        expect(port.opens, hasLength(1));
        expect(port.closes, 0);
        expect(storage.mutations, isEmpty);
        if (readFailure) {
          expect(
            find.byKey(const Key('appearance-preview-guide')),
            findsNothing,
          );
          await tester.tap(find.byKey(const Key('appearance-preview-help')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('appearance-preview-guide')),
            findsOneWidget,
          );
          expect(storage.guideWrites, 0);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('appearance-preview-guide')), findsNothing);
        expect(port.closes, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        module.dispose();
      },
    );
  }
  testWidgets('first preview guide is protected, remembered and can reopen', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final storage = Workspace()..guideSeen = false;
    final port = Preview();
    final module = OverlayWorkspaceModule(storage);
    await module.initialize();
    await tester.pumpWidget(
      app(
        OverlayAppearancePreviewPage(
          module: module,
          port: port,
          appearanceId: 'Default',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appearance-preview-guide')), findsOneWidget);
    expect(storage.guideWrites, 1);
    expect(storage.mutations, isEmpty);
    expect(port.plays, isEmpty);
    expect(port.protections.last, hasLength(3));
    await tester.tap(find.byKey(const Key('appearance-preview-guide-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appearance-preview-guide')), findsNothing);
    await tester.tap(find.byKey(const Key('appearance-preview-help')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appearance-preview-guide')), findsOneWidget);
    expect(storage.mutations, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      app(
        OverlayAppearancePreviewPage(
          module: module,
          port: Preview(),
          appearanceId: 'NightShadow',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appearance-preview-guide')), findsNothing);
    expect(storage.guideWrites, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    module.dispose();
  });
  // Installed-metadata checks need the explicitly built native DLL. Skipping
  // without it is not native proof and must not use a private schema fixture.
  final nativeUnavailable =
      Platform.environment['STARBRIDGE_LIVE_PREVIEW_REGRESSION'] == null;
  for (final id in ['Default', 'NightShadow', 'Verdict', 'HajiCitizen']) {
    testWidgets(
      '$id preview fields follow installed capabilities without altering the applied draft',
      (tester) async {
        size(tester, const Size(1280, 900));
        final storage = Workspace(), port = Preview();
        final module = OverlayWorkspaceModule(storage);
        await module.initialize();
        await tester.pumpWidget(
          app(
            OverlayAppearancePreviewPage(
              module: module,
              port: port,
              appearanceId: id,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final group = tester
            .widgetList<OverlayWorkspaceSettingsGroup>(
              find.byType(OverlayWorkspaceSettingsGroup),
            )
            .singleWhere((g) => g.group == 'appearance');
        final fields = group.fields.map((f) => f.field);
        final capability = appearance(id);
        expect(fields.contains('theme'), !capability.locksTheme);
        expect(fields.contains('autoThemeByShip'), !capability.locksTheme);
        expect(fields.contains('nightShadowBloom'), capability.supportsBloom);
        if (capability.locksTheme) {
          expect(
            find.byKey(const Key('overlay-appearance-fixed-palette')),
            findsOneWidget,
          );
        }
        expect(module.projection.value.settings!['skin'], 'Default');
        expect(storage.mutations, isEmpty);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        module.dispose();
      },
    );
  }
  testWidgets(
    'finite playback controls use the session without saving, applying or pet commands',
    (tester) async {
      size(tester, const Size(1280, 900));
      final storage = Workspace(), port = Preview();
      final module = OverlayWorkspaceModule(storage);
      await module.initialize();
      final initialRuntimeReads = List<OverlayRuntimeAction>.of(
        storage.runtimeActions,
      );
      module.updateSetting('showNotice', true);
      module.updateSetting('showEventNotifications', true);
      module.updateSetting('eventNotificationTypes', 1);
      module.updateSetting('eventNotificationMaxVisibleCount', 2);
      module.updateSetting('animationFrameRate', 'Fps60');
      await tester.pumpWidget(
        app(
          OverlayAppearancePreviewPage(
            module: module,
            port: port,
            appearanceId: 'HajiCitizen',
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final action in [
        OverlayAppearancePreviewPlayback.noticeShow,
        OverlayAppearancePreviewPlayback.noticeHide,
        OverlayAppearancePreviewPlayback.eventAdd,
        OverlayAppearancePreviewPlayback.eventHide,
        OverlayAppearancePreviewPlayback.eventSequence,
        OverlayAppearancePreviewPlayback.transition,
        OverlayAppearancePreviewPlayback.stop,
      ]) {
        final button = find.byKey(
          Key('appearance-preview-play-${action.name}'),
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(port.plays.last, action);
      }
      expect(port.opens.length, 1);
      // Edits save on their own; playback writes nothing and never applies
      // the browsed appearance.
      expect(
        storage.mutations.every((m) => m.settings!['skin'] == 'Default'),
        isTrue,
      );
      expect(storage.runtimeActions, initialRuntimeReads);
      expect(module.projection.value.settings!['skin'], 'Default');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      module.dispose();
    },
  );
  testWidgets(
    'preview-only reduced motion disables automatic sequence, preserves finite static examples and normal draft',
    (tester) async {
      size(tester, const Size(1280, 900));
      final storage = Workspace(), port = Preview();
      final module = OverlayWorkspaceModule(storage);
      await module.initialize();
      module.updateSetting('animationFrameRate', 'Fps60');
      module.updateSetting('showNotice', true);
      final before = module.projection.value.settings!.toMap();
      await tester.pumpWidget(
        app(
          OverlayAppearancePreviewPage(
            module: module,
            port: port,
            appearanceId: 'Verdict',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('appearance-preview-reduced-motion'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(port.updates.last.reduceMotion, isTrue);
      expect(module.projection.value.settings!.toMap(), before);
      final sequence = tester.widget<StarBridgeActionButton>(
        find.byKey(const Key('appearance-preview-play-eventSequence')),
      );
      expect(sequence.onActivate, isNull);
      expect(
        tester
            .widget<StarBridgeActionButton>(
              find.byKey(const Key('appearance-preview-play-transition')),
            )
            .onActivate,
        isNull,
      );
      final show = find.byKey(const Key('appearance-preview-play-noticeShow'));
      await tester.ensureVisible(show);
      await tester.pumpAndSettle();
      await tester.tap(show);
      await tester.pumpAndSettle();
      expect(port.plays.single, OverlayAppearancePreviewPlayback.noticeShow);
      expect(
        storage.mutations.every((m) => m.settings!['skin'] == 'Default'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      module.dispose();
    },
  );
  testWidgets(
    'installed Haji descriptor edits black background live with no default decorations or Apply',
    (tester) async {
      size(tester, const Size(1280, 900));
      final configuration = await tester.runAsync(installedHajiDescriptor);
      final storage = Workspace(configurations: [configuration!]),
          port = Preview();
      final module = OverlayWorkspaceModule(storage);
      await module.initialize();
      await tester.pumpWidget(
        app(
          OverlayAppearancePreviewPage(
            module: module,
            port: port,
            appearanceId: 'HajiCitizen',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(
        const Key('appearance-config-global-blackBackground'),
      );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('黑色').last);
      await tester.pumpAndSettle();
      final profile = port.updates.last.options.profile(
        configuration.profileId,
      )!;
      expect((profile['values'] as Map)['blackBackground'], true);
      expect((profile['values'] as Map)['decorations'], isEmpty);
      expect(storage.mutations, isEmpty);
      expect(module.projection.value.settings!['skin'], 'Default');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      module.dispose();
    },
    skip: nativeUnavailable,
  );
  testWidgets(
    'render main-window inspector at physical 2K for visual QA, not a native skin substitute',
    (tester) async {
      final destination =
          Platform.environment['STARBRIDGE_LIVE_INSPECTOR_CAPTURE'];
      if (destination == null) {
        throw StateError('Inspector capture destination missing.');
      }
      size(tester, const Size(2560, 1440));
      await loadFonts();
      final configuration = await tester.runAsync(installedHajiDescriptor);
      final module = OverlayWorkspaceModule(
        Workspace(configurations: [configuration!]),
      );
      await module.initialize();
      final port = Preview(), key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(
            OverlayAppearancePreviewPage(
              module: module,
              port: port,
              appearanceId: 'HajiCitizen',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Inspector render failed.');
        await File(destination).parent.create(recursive: true);
        await File(destination).writeAsBytes(data.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      module.dispose();
    },
    skip:
        nativeUnavailable ||
        Platform.environment['STARBRIDGE_LIVE_INSPECTOR_CAPTURE'] == null,
  );
  testWidgets('latest actual draft is retained while native open is pending', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final module = OverlayWorkspaceModule(Workspace());
    await module.initialize();
    final port = Preview()..opening = Completer<String>();
    await tester.pumpWidget(
      app(
        OverlayAppearancePreviewPage(
          module: module,
          port: port,
          appearanceId: 'Default',
        ),
      ),
    );
    await tester.pumpAndSettle();
    module.updateSetting('opacity', .7);
    await tester.pumpAndSettle();
    port.opening!.complete('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    await tester.pumpAndSettle();
    expect(port.opens, hasLength(1));
    expect(port.updates.last.settings['opacity'], .7);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    module.dispose();
  });
  testWidgets(
    'color popup waits for full protection and Escape restores inspector only',
    (tester) async {
      size(tester, const Size(1280, 900));
      final module = OverlayWorkspaceModule(Workspace());
      await module.initialize();
      module.updateSetting('showCrosshair', true);
      module.updateSetting('crosshairUseThemeColor', false);
      final port = Preview();
      await tester.pumpWidget(
        app(
          OverlayAppearancePreviewPage(
            module: module,
            port: port,
            appearanceId: 'Default',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final color = find.byKey(
        const Key('appearance-preview-color-crosshairColor'),
      );
      await tester.tap(find.byKey(const Key('appearance-preview-crosshair')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(color);
      await tester.pumpAndSettle();
      port.protection = Completer<int>();
      await tester.tap(color);
      await tester.pump();
      expect(find.byType(OverlayColorPickerDialog), findsNothing);
      expect(port.protections.last.single.toMap(), {
        'x': 0.0,
        'y': 0.0,
        'width': 1.0,
        'height': 1.0,
      });
      port.protection!.complete(2);
      port.protection = null;
      await tester.pumpAndSettle();
      expect(find.byType(OverlayColorPickerDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(OverlayColorPickerDialog), findsNothing);
      expect(port.closes, 0);
      expect(
        port.protections.last.any((a) => a.x > .5 && a.height == 1),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      module.dispose();
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final width in [1280.0, 390.0]) {
      testWidgets(
        'same main-window inspector fits $locale at $width and large text',
        (tester) async {
          size(tester, Size(width, 900));
          final storage = Workspace()..guideSeen = false;
          final module = OverlayWorkspaceModule(storage);
          await module.initialize();
          final port = Preview();
          final base = app(const SizedBox()) as MaterialApp;
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              supportedLocales: base.supportedLocales,
              localizationsDelegates: base.localizationsDelegates,
              theme: base.theme,
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: const TextScaler.linear(1.5),
                  disableAnimations: true,
                ),
                child: OverlayAppearancePreviewPage(
                  module: module,
                  port: port,
                  appearanceId: 'Default',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(port.opens, hasLength(1));
          expect(
            find.byKey(const Key('appearance-preview-guide')),
            findsOneWidget,
          );
          for (final removedCopy in [
            '试试看不会自动保存或应用外观。',
            '試試看不會自動儲存或套用外觀。',
            'Trying things out does not automatically save or apply an appearance.',
          ]) {
            expect(find.text(removedCopy), findsNothing);
          }
          final guideRect = tester.getRect(
            find.byKey(const Key('appearance-preview-guide')),
          );
          expect(
            port.protections.last.any(
              (a) =>
                  a.x * width <= guideRect.left + 1 &&
                  a.y * 900 <= guideRect.top + 1 &&
                  (a.x + a.width) * width >= guideRect.right - 1 &&
                  (a.y + a.height) * 900 >= guideRect.bottom - 1,
            ),
            isTrue,
          );
          expect(storage.mutations, isEmpty);
          expect(port.plays, isEmpty);
          expect(
            port.opens.single.language,
            locale.languageCode != 'zh'
                ? 'en'
                : locale.countryCode == 'TW'
                ? 'zh-Hant'
                : 'zh-CN',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          module.dispose();
        },
      );
    }
  }
  testWidgets(
    'actual workspace geometry enters one native session, editing never applies a new skin',
    (tester) async {
      size(tester, const Size(1280, 900));
      final storage = Workspace(), port = Preview();
      final module = OverlayWorkspaceModule(storage);
      await module.initialize();
      await tester.pumpWidget(
        app(
          OverlayAppearancePreviewPage(
            module: module,
            port: port,
            appearanceId: 'HajiCitizen',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(port.opens, hasLength(1));
      expect(
        port.opens.single.layout.map((a) => a.toMap()),
        fullLayout().map((a) => a.toMap()),
      );
      expect(
        find.byKey(const Key('appearance-preview-inspector')),
        findsOneWidget,
      );
      expect(find.byType(OverlayColorPickerDialog), findsNothing);
      module.updateSetting('opacity', .7);
      await tester.pumpAndSettle();
      expect(port.updates.last.settings['opacity'], .7);
      expect(port.closes, 0);
      expect(module.projection.value.settings!['skin'], 'Default');
      // The opacity edit saved on its own; Save has nothing left to write.
      expect(storage.mutations.single.settings!['opacity'], .7);
      await tester.tap(find.byKey(const Key('appearance-preview-save')));
      await tester.pumpAndSettle();
      expect(storage.mutations, hasLength(1));
      expect(storage.mutations.single.settings!['skin'], 'Default');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(port.closes, 1);
      module.dispose();
    },
  );
  testWidgets(
    'inspector switch waits for native protection before exposing new controls',
    (tester) async {
      size(tester, const Size(1280, 900));
      final module = OverlayWorkspaceModule(Workspace());
      await module.initialize();
      final port = Preview();
      await tester.pumpWidget(
        app(
          OverlayAppearancePreviewPage(
            module: module,
            port: port,
            appearanceId: 'Default',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final inspector = find.byKey(const Key('appearance-preview-inspector'));
      expect(tester.getTopLeft(inspector).dx, greaterThan(800));
      port.protection = Completer<int>();
      await tester.tap(find.byKey(const Key('appearance-preview-switch-side')));
      await tester.pump();
      expect(tester.getTopLeft(inspector).dx, greaterThan(800));
      expect(
        port.protections.last.any((a) => a.x == 0 && a.height == 1),
        isTrue,
      );
      expect(
        port.protections.last.any((a) => a.x > .5 && a.height == 1),
        isTrue,
      );
      port.protection!.complete(2);
      port.protection = null;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(inspector).dx, lessThan(20));
      await tester.tap(find.byKey(const Key('appearance-preview-collapse')));
      await tester.pumpAndSettle();
      expect(inspector, findsNothing);
      expect(port.protections.last, hasLength(1));
      expect(port.opens, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      module.dispose();
    },
  );
  testWidgets(
    'healthy page remains open beyond ten minutes without draft or event replay',
    (tester) async {
      size(tester, const Size(1280, 900));
      final storage = Workspace(), port = Preview();
      final module = OverlayWorkspaceModule(storage);
      await module.initialize();
      await tester.pumpWidget(
        app(
          OverlayAppearancePreviewPage(
            module: module,
            port: port,
            appearanceId: 'HajiCitizen',
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 44; i++) {
        await tester.pump(const Duration(seconds: 15));
        await tester.pump();
      }
      expect(port.closes, 0);
      expect(port.opens, hasLength(1));
      expect(port.updates, isEmpty);
      expect(port.plays, isEmpty);
      expect(port.renewals, List.generate(22, (index) => index + 1));
      expect(storage.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(port.closes, 1);
      await tester.pump(const Duration(minutes: 3));
      expect(port.renewals, hasLength(22));
      module.dispose();
    },
  );

  testWidgets('root route reuses one main window and restores it on exit', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final window = Window(), storage = Workspace(), port = Preview();
    final module = OverlayWorkspaceModule(storage, editorWindow: window);
    await module.initialize();
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showOverlayAppearancePreviewPage(
              context,
              module: module,
              port: port,
              appearanceId: 'Default',
            ),
            child: const Text('launch'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
    expect(window.enters, 1);
    expect(find.byKey(const Key('appearance-preview-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('appearance-preview-exit')));
    await tester.pumpAndSettle();
    expect(port.closes, 1);
    expect(window.exits, 1);
    expect(find.text('launch'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    module.dispose();
  });
}
