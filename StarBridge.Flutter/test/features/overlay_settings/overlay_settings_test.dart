import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';
import 'package:starbridge_flutter/platform/window/overlay_editor_window_port.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/product_features.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/overlay_settings_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/tray/tray_application_binding.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/game_log/game_log_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_settings_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/host_unavailable_overlay_settings_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/in_memory_overlay_settings_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_module.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_feature.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_page.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preview_identity.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_rules.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_geometry.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_runtime_projection.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_inspector.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_fullscreen.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_editor_state.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_editor_tools.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_fixed_previews.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_preview_content.dart';
import 'package:starbridge_flutter/design_system/styles/overlay_appearance_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_layout_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'returning to Fleet Standard clears the previous locked appearance theme',
    () {
      final initial = OverlayWorkspaceSettings.fromMap(
        _completeWorkspaceSettings(),
      );
      for (final skin in ['NightShadow', 'Verdict', 'LagrangeWeave']) {
        final themed = applyOverlayWorkspaceSettingChange(
          initial,
          'skin',
          skin,
        );
        final standard = applyOverlayWorkspaceSettingChange(
          themed,
          'skin',
          'Default',
        );
        expect(standard['skin'], 'Default');
        expect(standard['requestedSkin'], 'Default');
        expect(
          standard['theme'],
          'Default',
          reason: 'Must not retain $skin theme',
        );
      }
    },
  );
  testWidgets(
    'tray uses real workspace runtime instead of legacy settings toggle',
    (tester) async {
      const channel = MethodChannel('starbridge/tray-primary');
      final snapshots = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'configure') snapshots.add(call.arguments as Map);
        return null;
      });
      final preferences = ValueNotifier(
        const AppPreferencesProjection(
          effective: AppPreferences.defaults,
          confirmed: null,
          revision: null,
          phase: AppPreferencesPhase.ready,
          operation: AppPreferencesOperation.idle,
          source: null,
          failure: null,
        ),
      );
      final chrome = InMemoryShellChrome(
        initial: InMemoryShellChrome.hostConnectedProjection,
      );
      final port = _MemoryWorkspacePort(_workspaceSnapshot());
      final module = OverlaySettingsModule(
        HostUnavailableOverlaySettingsAdapter(),
        workspacePort: port,
      );
      await module.initialize();
      final binding = TrayApplicationBinding(
        preferences: preferences,
        chrome: chrome.projection,
        overlay: module,
        openOverlaySettings: () async {},
      );
      await tester.pump();
      expect(snapshots.last['canToggleOverlay'], true);
      expect(snapshots.last['overlay'], 'disabled');
      Object? error;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('action', {
            'action': 'toggleOverlay',
            'scope': snapshots.last['scope'],
          }),
        ),
        (data) {
          try {
            const StandardMethodCodec().decodeEnvelope(data!);
          } catch (e) {
            error = e;
          }
        },
      );
      await tester.pump();
      expect(error, isNull);
      expect(port.lastRuntimeAction, OverlayRuntimeAction.open);
      expect(snapshots.last['overlay'], 'enabled');
      binding.dispose();
      await tester.pump();
      module.dispose();
      preferences.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );

  testWidgets(
    'entering overlay settings recovers initial unavailable without refresh click',
    (tester) async {
      final port = _MemoryWorkspacePort(
        const OverlayWorkspaceSnapshot.unavailable(),
      );
      final module = OverlaySettingsModule(
        HostUnavailableOverlaySettingsAdapter(),
        workspacePort: port,
      );
      addTearDown(module.dispose);
      await module.initialize();
      expect(module.workspace!.projection.value.available, false);
      port.snapshot = _workspaceSnapshot();
      await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
      // Recovery must not wait for unrelated asynchronous preview images or
      // their indeterminate loading indicators to settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(module.workspace!.projection.value.available, true);
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'overlay watch recovers and updates runtime without replaying commands',
    (tester) async {
      final port = _MemoryWorkspacePort(
        const OverlayWorkspaceSnapshot.unavailable(),
      );
      final module = OverlaySettingsModule(
        HostUnavailableOverlaySettingsAdapter(),
        workspacePort: port,
      );
      await module.initialize();
      final release = module.watch();
      await tester.pump();
      port.snapshot = _workspaceSnapshot();
      await tester.pump(const Duration(seconds: 10));
      expect(module.workspace!.projection.value.available, true);
      await module.workspace!.openRuntime('zh');
      expect(module.workspace!.projection.value.runtime.isVisible, true);
      await port.executeRuntime(OverlayRuntimeAction.close, language: 'zh');
      await tester.pump(const Duration(seconds: 10));
      expect(module.workspace!.projection.value.runtime.isVisible, false);
      expect(port.lastRuntimeAction, OverlayRuntimeAction.getState);
      final reads = port.reads;
      release();
      await tester.pump(const Duration(seconds: 30));
      expect(port.reads, reads);
      module.dispose();
    },
  );

  testWidgets(
    'silent overlay renewal preserves drafts including edits made during a read',
    (tester) async {
      final port = _MemoryWorkspacePort(_workspaceSnapshot());
      final module = OverlaySettingsModule(
        HostUnavailableOverlaySettingsAdapter(),
        workspacePort: port,
      );
      await module.initialize();
      final workspace = module.workspace!;
      port.pendingRead = Completer<OverlayWorkspaceSnapshot>();
      final renewal = module.synchronize();
      workspace.updateSetting('showNotice', false);
      port.pendingRead!.complete(port.snapshot);
      await renewal;
      port.pendingRead = null;
      expect(workspace.projection.value.settings!.toMap()['showNotice'], false);
      expect(workspace.projection.value.dirty, true);
      await module.synchronize();
      expect(workspace.projection.value.settings!.toMap()['showNotice'], false);
      expect(workspace.projection.value.dirty, true);
      expect(port.lastMutation, isNull);
      expect(workspace.canUndo, true);
      module.dispose();
    },
  );

  testWidgets(
    'overlay renewal recovers from a thrown initial read instead of stuck loading',
    (tester) async {
      final port = _MemoryWorkspacePort(_workspaceSnapshot())
        ..readFailure = StateError('temporary');
      final module = OverlaySettingsModule(
        HostUnavailableOverlaySettingsAdapter(),
        workspacePort: port,
      );
      await module.initialize();
      expect(module.workspace!.projection.value.busy, false);
      port.readFailure = null;
      await module.synchronize();
      expect(module.workspace!.projection.value.available, true);
      module.dispose();
    },
  );
  setUpAll(_loadPreviewFonts);
  testWidgets(
    'menu settings opens native preview only on explicit click and preserves info page',
    (tester) async {
      const channel = MethodChannel('starbridge/menu-primary');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return 1;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final adapter = InMemoryOverlaySettingsAdapter();
      final module = OverlaySettingsModule(
        adapter,
        menuPreview: MethodChannelMenuPreviewWindow(),
      );
      addTearDown(module.dispose);
      await module.initialize();
      await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
      await tester.pumpAndSettle();
      final entry = find.byKey(const Key('overlay-menu-settings'));
      if (!menuOverlayEnabled) {
        expect(entry, findsNothing);
        expect(
          find.byKey(const Key('menu-overlay-open-preview')),
          findsNothing,
        );
        expect(find.byKey(const Key('overlay-controls')), findsOneWidget);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
        return;
      }
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      final open = find.byKey(const Key('menu-overlay-open-preview'));
      await tester.tap(open);
      await tester.pump();
      expect(calls.single.method, 'preview');
      expect(tester.widget<FilledButton>(open).onPressed, isNull);
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('state', 'hidden'),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('menu-overlay-preview-failed')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(open).onPressed, isNotNull);
      await tester.tap(find.text('信息浮层'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overlay-controls')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('renders persisted controls and the live game projection', (
    tester,
  ) async {
    await tester.runAsync(_loadPreviewFonts);
    tester.view.physicalSize = const Size(1240, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = InMemoryOverlaySettingsAdapter();
    final module = OverlaySettingsModule(adapter);
    final game = ValueNotifier(
      const GameLogView(
        visible: true,
        state: 'identified',
        match: 'match',
        enabled: true,
        channel: 'LIVE',
        verifiedChannels: ['LIVE'],
        sessionState: 'ready',
        serverState: 'connected',
        serverRegion: 'US',
        serverShard: 'pub_use1b_12545750_070',
        locationState: 'confirmed',
        locationEnglishName: 'Orison',
        locationNameZhHans: '奥里森',
        shipState: 'confirmed',
        shipEnglishName: 'F8C Lightning',
        shipNameZhHans: 'F8C 闪电',
      ),
    );
    addTearDown(game.dispose);
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(
      _app(OverlaySettingsPage(module: module, gameLog: game)),
    );
    await tester.pumpAndSettle();

    expect(find.text('游戏内信息浮层'), findsOneWidget);
    expect(find.byKey(const Key('overlay-controls')), findsOneWidget);
    expect(find.byKey(const Key('overlay-preview')), findsOneWidget);
    expect(find.text('美服'), findsOneWidget);
    expect(find.text('pub_use1b_12545750_070'), findsOneWidget);
    expect(find.text('奥里森'), findsOneWidget);
    expect(find.text('F8C 闪电'), findsOneWidget);
    expect(find.textContaining('Native Host'), findsNothing);
    expect(find.textContaining('WPF'), findsNothing);
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byType(OverlaySettingsPage),
        matchesGoldenFile(
          menuOverlayEnabled
              ? 'goldens/overlay-settings-1240.png'
              : 'goldens/overlay-settings-release-1240.png',
        ),
      );
    }

    final bottomLeft = find.byKey(const Key('overlay-position-bottomLeft'));
    await tester.ensureVisible(bottomLeft);
    await tester.tap(bottomLeft);
    await tester.pumpAndSettle();
    expect(
      adapter.current.settings?.position,
      OverlaySettingsPosition.bottomLeft,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the page usable at a narrow width', (tester) async {
    tester.view.physicalSize = const Size(430, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = OverlaySettingsModule(InMemoryOverlaySettingsAdapter());
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('overlay-controls')), findsOneWidget);
    expect(find.byKey(const Key('overlay-preview')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('overlay-preview')),
      420,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable state offers retry without inactive controls', (
    tester,
  ) async {
    final module = OverlaySettingsModule(
      HostUnavailableOverlaySettingsAdapter(),
    );
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('overlay-settings-unavailable')),
      findsOneWidget,
    );
    expect(find.text('重新读取'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('complete workspace page edits and saves through one revision', (
    tester,
  ) async {
    await tester.runAsync(_loadPreviewFonts);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workspace = _MemoryWorkspacePort(_workspaceSnapshot());
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: workspace,
    );
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('overlay-workspace-content')), findsOneWidget);
    expect(find.byKey(const Key('overlay-group-navigation')), findsOneWidget);
    expect(find.byKey(const Key('overlay-preview-stage')), findsOneWidget);
    expect(find.byKey(const Key('overlay-runtime-preview')), findsOneWidget);
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byType(OverlaySettingsPage),
        matchesGoldenFile(
          menuOverlayEnabled
              ? 'goldens/overlay-workspace-1280.png'
              : 'goldens/overlay-workspace-release-1280.png',
        ),
      );
    }
    expect(find.byKey(const Key('overlay-field-showNotice')), findsOneWidget);
    expect(
      find.byKey(const Key('overlay-module-text-opacity-Notice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-module-background-opacity-Notice')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('overlay-group-nav-fleetOverview')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-module-text-opacity-Squads')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-module-background-opacity-Squads')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('overlay-group-nav-members')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-field-memberNameMode')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-module-text-opacity-Members')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-module-background-opacity-Members')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('overlay-group-nav-chat')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-module-text-opacity-Chat')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-module-background-opacity-Chat')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('overlay-group-nav-notice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overlay-field-showNotice')));
    await tester.pump();
    expect(find.text('有尚未保存的更改'), findsOneWidget);
    await tester.tap(find.byTooltip('撤销'));
    await tester.pump();
    expect(find.text('所有更改已保存'), findsOneWidget);
    await tester.tap(find.byTooltip('重做'));
    await tester.pump();
    expect(find.text('有尚未保存的更改'), findsOneWidget);
    await tester.tap(find.text('保存更改'));
    await tester.pumpAndSettle();
    expect(
      workspace.lastMutation?.kind,
      OverlayWorkspaceMutationKind.saveActive,
    );
    expect(workspace.lastExpectedRevision, 42);
    expect(find.text('所有更改已保存'), findsOneWidget);

    expect(find.byKey(const Key('overlay-group-nav-appearance')), findsNothing);
    await tester.tap(find.byKey(const Key('overlay-appearance-center-entry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-appearance-center')), findsOneWidget);
    expect(find.byKey(const Key('overlay-field-theme')), findsOneWidget);
    expect(find.byKey(const Key('overlay-preview-stage')), findsNothing);

    await tester.tap(find.byKey(const Key('overlay-appearance-center-back')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('overlay-group-nav-events')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-field-eventNotificationSide')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-field-eventNotificationY')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('overlay-module-text-opacity-Events')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-module-background-opacity-Events')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('overlay-group-nav-layout')), findsNothing);
    expect(find.byKey(const Key('overlay-preview-stage')), findsOneWidget);
    expect(find.byKey(const Key('overlay-settings-dock')), findsOneWidget);
    expect(find.byKey(const Key('overlay-enter-fullscreen')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected group paints its fill on the material ink layer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
    );
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();
    final navigationItem = find.byKey(const Key('overlay-group-nav-members'));
    await tester.tap(navigationItem);
    await tester.pump(const Duration(milliseconds: 40));

    expect(
      find.descendant(of: navigationItem, matching: find.byType(Ink)),
      findsOneWidget,
      reason: 'The selected fill must not cover InkWell splash feedback.',
    );
  });

  testWidgets('module appearance controls update their real backing values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
    );
    addTearDown(module.dispose);
    await module.initialize();
    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();

    tester
        .widget<Slider>(
          find.descendant(
            of: find.byKey(const Key('overlay-module-text-opacity-Notice')),
            matching: find.byType(Slider),
          ),
        )
        .onChanged!(0.55);
    await tester.pump();
    expect(
      module.workspace!.projection.value.layout
          .singleWhere((item) => item.key == 'Notice')
          .textOpacity,
      0.55,
    );

    await tester.tap(find.byKey(const Key('overlay-group-nav-events')));
    await tester.pumpAndSettle();
    tester
        .widget<Slider>(
          find.descendant(
            of: find.byKey(
              const Key('overlay-module-background-opacity-Events'),
            ),
            matching: find.byType(Slider),
          ),
        )
        .onChanged!(0.35);
    await tester.pump();
    expect(
      module
          .workspace!
          .projection
          .value
          .settings!['eventNotificationBackgroundOpacity'],
      0.35,
    );
    expect(module.workspace!.projection.value.dirty, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shortcut recorder requires a modifier and records one chord', (
    tester,
  ) async {
    var binding = '';
    await tester.pumpWidget(
      _app(
        OverlayWorkspaceHotkeyCard(
          hotkey: const OverlayWorkspaceHotkey(
            binding: 'Ctrl+Shift+O',
            enabled: true,
            runtimeState: 'registered',
          ),
          onBindingChanged: (value) => binding = value,
          onEnabledChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('overlay-hotkey-record')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(find.text('请使用修饰键搭配字母/数字，或直接按 F1–F12。'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(binding, 'Ctrl+K');
    expect(find.byKey(const Key('overlay-hotkey-capturing')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scene-labelled presets switch from the quick access rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = _MemoryWorkspacePort(
      _workspaceSnapshot(includePartyPreset: true),
    );
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: port,
    );
    addTearDown(module.dispose);
    await module.initialize();
    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();

    expect(find.text('场景快捷预设'), findsOneWidget);
    expect(find.text('组队房间'), findsOneWidget);
    expect(find.byKey(const Key('overlay-active-preset')), findsNothing);
    expect(find.byKey(const Key('overlay-active-preset-name')), findsOneWidget);
    expect(
      find.byKey(const Key('overlay-preset-name-save-hint')),
      findsOneWidget,
    );
    final nameFieldRect = tester.getRect(
      find.byKey(const Key('overlay-active-preset-name')),
    );
    final manageButtonRect = tester.getRect(
      find.byKey(const Key('overlay-preset-manage')),
    );
    final appearanceEntryRect = tester.getRect(
      find.byKey(const Key('overlay-appearance-center-entry')),
    );
    expect(nameFieldRect.top, closeTo(manageButtonRect.top, 1));
    expect(nameFieldRect.bottom, closeTo(manageButtonRect.bottom, 1));
    expect(nameFieldRect.top, closeTo(appearanceEntryRect.top, 1));
    expect(nameFieldRect.bottom, closeTo(appearanceEntryRect.bottom, 1));
    await tester.tap(find.byKey(const Key('overlay-quick-preset-preset2')));
    await tester.pumpAndSettle();
    expect(
      port.lastMutation?.kind,
      OverlayWorkspaceMutationKind.activatePreset,
    );
    expect(port.lastMutation?.presetId, 'preset2');

    await tester.tap(find.byKey(const Key('overlay-add-preset')));
    await tester.pumpAndSettle();
    expect(port.lastMutation?.kind, OverlayWorkspaceMutationKind.createPreset);
    expect(port.lastMutation?.name, '新预设');
    expect(tester.takeException(), isNull);
  });

  testWidgets('current preset name can be edited directly', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = _MemoryWorkspacePort(_workspaceSnapshot());
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: port,
    );
    addTearDown(module.dispose);
    await module.initialize();
    module.workspace!.updateSetting('showNotice', false);
    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('overlay-active-preset-name')),
      '深空行动',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('overlay-active-preset-rename')));
    await tester.pumpAndSettle();

    expect(port.lastMutation?.kind, OverlayWorkspaceMutationKind.renamePreset);
    expect(port.lastMutation?.presetId, 'preset1');
    expect(port.lastMutation?.name, '深空行动');
    expect(module.workspace!.projection.value.dirty, isTrue);
    expect(module.workspace!.projection.value.settings!['showNotice'], isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps runtime controls in the page flow on compact screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
    );
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('overlay-runtime-card')), findsOneWidget);
    expect(find.byKey(const Key('overlay-group-navigation')), findsNothing);
    expect(find.byKey(const Key('overlay-preview-stage')), findsNothing);
    expect(find.byKey(const Key('overlay-runtime-preview')), findsOneWidget);
    expect(find.text('屏幕布局'), findsNothing);
    expect(find.text('信息浮层已关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens and closes the real overlay from its runtime card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1240, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workspace = _MemoryWorkspacePort(_workspaceSnapshot());
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: workspace,
    );
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('overlay-runtime-card')), findsOneWidget);
    expect(find.text('信息浮层已关闭'), findsOneWidget);
    module.workspace!.updateSetting('showNotice', false);
    await tester.pump();
    expect(find.text('打开浮层'), findsOneWidget);
    await tester.tap(find.byKey(const Key('overlay-runtime-action')));
    await tester.pumpAndSettle();
    expect(workspace.lastMutation, isNull);
    expect(module.workspace!.projection.value.dirty, isTrue);
    expect(workspace.lastRuntimeAction, OverlayRuntimeAction.open);
    expect(workspace.lastRuntimeDraft?.settings['showNotice'], isFalse);
    expect(find.text('信息浮层正在显示'), findsOneWidget);
    expect(find.text('关闭浮层'), findsOneWidget);

    module.workspace!.updateSetting('showMembers', true);
    await tester.pumpAndSettle();
    expect(workspace.lastMutation, isNull);
    expect(workspace.lastRuntimeAction, OverlayRuntimeAction.getState);
    expect(workspace.lastRuntimeDraft?.settings['showMembers'], isTrue);

    module.workspace!.discardChanges();
    await tester.pumpAndSettle();
    expect(module.workspace!.projection.value.dirty, isFalse);
    expect(workspace.lastRuntimeAction, OverlayRuntimeAction.getState);
    expect(workspace.lastRuntimeDraft?.settings['showNotice'], isFalse);
    expect(workspace.lastRuntimeDraft?.settings['showMembers'], isFalse);

    await tester.tap(find.byKey(const Key('overlay-runtime-action')));
    await tester.pumpAndSettle();
    expect(workspace.lastRuntimeAction, OverlayRuntimeAction.close);
    expect(find.text('信息浮层已关闭'), findsOneWidget);
  });

  testWidgets('leaving a dirty overlay workspace requires an explicit choice', (
    tester,
  ) async {
    final workspace = _MemoryWorkspacePort(_workspaceSnapshot());
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: workspace,
    );
    addTearDown(module.dispose);
    await module.initialize();
    bool? allowed;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            key: const Key('attempt-overlay-leave'),
            onPressed: () => unawaited(() async {
              allowed = await confirmOverlayWorkspaceLeave(context, module);
            }()),
            child: const Text('leave'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    module.workspace!.updateSetting('showNotice', false);
    await tester.tap(find.byKey(const Key('attempt-overlay-leave')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-unsaved-leave-dialog')),
      findsOneWidget,
    );
    expect(allowed, isNull);

    await tester.tap(find.byKey(const Key('overlay-unsaved-leave-cancel')));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
    expect(module.workspace!.projection.value.dirty, isTrue);

    allowed = null;
    await tester.tap(find.byKey(const Key('attempt-overlay-leave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overlay-unsaved-leave-discard')));
    await tester.pumpAndSettle();
    expect(allowed, isTrue);
    expect(module.workspace!.projection.value.dirty, isFalse);
    expect(workspace.lastMutation, isNull);

    module.workspace!.updateSetting('showNotice', false);
    allowed = null;
    await tester.tap(find.byKey(const Key('attempt-overlay-leave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overlay-unsaved-leave-save')));
    await tester.pumpAndSettle();
    expect(allowed, isTrue);
    expect(
      workspace.lastMutation?.kind,
      OverlayWorkspaceMutationKind.saveActive,
    );
  });

  test(
    'bridge adapter reads and updates device settings without account data',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 6,
      )..acceptHostCapabilities(['overlay.settings']);
      var revision = 2;
      var value = OverlaySettingsValue.defaults;
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen((request) {
        requests.add(request);
        if (request.name == 'overlay.update') {
          final settings = request.payload['settings'] as Map<String, Object?>;
          value = OverlaySettingsValue(
            enabled: settings['enabled']! as bool,
            opacity: (settings['opacity']! as num).toDouble(),
            position: OverlaySettingsPosition.values.singleWhere(
              (position) => position.name == settings['position'],
            ),
            showTeam: settings['showTeam']! as bool,
          );
          revision++;
        }
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 6,
              status: 'ok',
              payload: {
                'schemaVersion': 1,
                'revision': revision,
                'storageState': 'ready',
                'windowState': 'unavailable',
                'settings': {
                  'enabled': value.enabled,
                  'opacity': value.opacity,
                  'position': value.position.name,
                  'showTeam': value.showTeam,
                },
              },
            ),
          ),
        );
      });
      addTearDown(subscription.cancel);
      addTearDown(session.close);
      final adapter = BridgeOverlaySettingsAdapter(session);

      final initial = await adapter.read();
      expect(initial.settings, isNotNull);
      final result = await adapter.update(
        value.copyWith(
          opacity: 0.7,
          position: OverlaySettingsPosition.bottomRight,
        ),
        expectedRevision: revision,
      );

      expect(result.completed, isTrue);
      expect(result.snapshot?.revision, 3);
      expect(result.snapshot?.settings?.opacity, 0.7);
      expect(requests, hasLength(2));
      expect(
        requests.every((request) => request.accountContext == null),
        isTrue,
      );
    },
  );

  test(
    'workspace adapter preserves the complete WPF settings contract',
    () async {
      expect(OverlayWorkspaceSettings.requiredFields, hasLength(73));
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 9,
      )..acceptHostCapabilities(['overlay.workspace']);
      final requests = <BridgeEnvelope>[];
      final settings = _completeWorkspaceSettings();
      final layout = _workspaceLayout();
      final subscription = pair.host.incoming.listen((request) {
        requests.add(request);
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 9,
              status: 'ok',
              payload: {
                'schemaVersion': 1,
                'revision': 42,
                'storageState': 'ready',
                'activePresetId': 'preset1',
                'renderMode': 'DirectComposition',
                'appearances': _workspaceAppearanceMaps(),
                'hotkey': {
                  'binding': 'Ctrl+Shift+O',
                  'enabled': true,
                  'runtimeState': 'unavailable',
                },
                'settings': settings,
                'layout': layout,
                'presets': [
                  {
                    'id': 'preset1',
                    'name': '默认预设',
                    'isActive': true,
                    'storageState': 'ready',
                    'settings': settings,
                    'layout': layout,
                  },
                ],
              },
            ),
          ),
        );
      });
      addTearDown(subscription.cancel);
      addTearDown(session.close);

      final adapter = BridgeOverlayWorkspaceAdapter(session);
      final result = await adapter.read();

      expect(result.availability, OverlayWorkspaceAvailability.available);
      expect(result.revision, 42);
      expect(result.activePresetId, 'preset1');
      expect(result.hotkey?.binding, 'Ctrl+Shift+O');
      expect(result.hotkey?.enabled, isTrue);
      expect(result.appearances, hasLength(4));
      expect(
        result.appearances
            .singleWhere((appearance) => appearance.id == 'NightShadow')
            .isAvailable,
        isTrue,
      );
      expect(
        result.appearances
            .singleWhere((appearance) => appearance.id == 'Verdict')
            .isReleased,
        isFalse,
      );
      expect(result.settings?.values, hasLength(73));
      expect(result.settings?['crosshairMode'], 'Cross');
      expect(result.layout, hasLength(4));
      expect(result.presets.single.name, '默认预设');
      expect(requests.single.name, 'overlay.getWorkspace');
      expect(requests.single.accountContext, isNull);

      final commands = <OverlayWorkspaceMutation>[
        OverlayWorkspaceMutation.saveActive(
          settings: result.settings!,
          layout: result.layout,
          renderMode: result.renderMode!,
          hotkey: result.hotkey!,
        ),
        const OverlayWorkspaceMutation.activatePreset('preset1'),
        const OverlayWorkspaceMutation.createPreset('新预设'),
        const OverlayWorkspaceMutation.duplicatePreset('preset1', '作战'),
        const OverlayWorkspaceMutation.renamePreset('preset1', '默认'),
        const OverlayWorkspaceMutation.resetPreset('preset1'),
        OverlayWorkspaceMutation.importPreset(
          name: '导入',
          settings: result.settings!,
          layout: result.layout,
        ),
        const OverlayWorkspaceMutation.deletePreset('preset1'),
      ];
      for (final command in commands) {
        final write = await adapter.apply(command, expectedRevision: 42);
        expect(write.completed, isTrue, reason: command.kind.name);
      }
      expect(
        requests.skip(1).map((request) => request.name),
        everyElement('overlay.updateWorkspace'),
      );
      expect(
        requests.skip(1).map((request) => request.payload['action']),
        commands.map((command) => command.kind.name),
      );
      expect(
        requests.every((request) => request.accountContext == null),
        isTrue,
      );
      expect(requests[1].payload.keys.toSet(), {
        'schemaVersion',
        'expectedRevision',
        'action',
        'settings',
        'layout',
        'renderMode',
        'hotkey',
      });
      expect(requests[2].payload.keys.toSet(), {
        'schemaVersion',
        'expectedRevision',
        'action',
        'presetId',
      });
    },
  );

  test('layout editor keeps WPF grid, smart snap, and pixel nudge rules', () {
    const item = OverlayWorkspaceLayoutItem(
      key: 'Members',
      x: 0.1,
      y: 0.1,
      width: 0.25,
      height: 0.2,
      horizontalAnchor: 'Left',
      verticalAnchor: 'Top',
      isLocked: false,
      textOpacity: 1,
      backgroundOpacity: 1,
    );
    final moved = OverlayWorkspaceLayoutGeometry.move(
      item: item,
      layout: const [item],
      delta: const Offset(7, 7),
      snapPixels: 16,
      smartSnap: false,
    );
    final movedRect = OverlayWorkspaceLayoutGeometry.resolve(moved);
    expect(movedRect.left, closeTo(192, 0.001));
    expect(movedRect.top, closeTo(112, 0.001));

    final nearRight = item.copyWith(x: 1430 / 1920);
    final snapped = OverlayWorkspaceLayoutGeometry.move(
      item: nearRight,
      layout: [nearRight],
      delta: Offset.zero,
    );
    expect(
      OverlayWorkspaceLayoutGeometry.resolve(snapped).right,
      closeTo(1920, 0.001),
    );

    final widened = OverlayWorkspaceLayoutGeometry.nudge(item, 'width', 5);
    expect(
      OverlayWorkspaceLayoutGeometry.resolve(widened).width,
      closeTo(485, 0.001),
    );
  });

  test('layout geometry matches the shared cross-client samples', () {
    final source = jsonDecode(
      File('../data/overlay/information-overlay-layout-conformance-v1.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    expect(source['schemaVersion'], 1);

    for (final rawCase in source['resolveCases']! as List<Object?>) {
      final sample = Map<String, Object?>.from(rawCase! as Map);
      final items = (sample['items']! as List<Object?>)
          .map(
            (raw) => OverlayWorkspaceLayoutItem.fromMap(
              Map<String, Object?>.from(raw! as Map),
            ),
          )
          .toList(growable: false);
      final resolved = OverlayWorkspaceLayoutGeometry.resolveItems(items);
      final expected = Map<String, Object?>.from(sample['expected']! as Map);
      for (final entry in expected.entries) {
        _expectRect(
          resolved[entry.key]!,
          (entry.value! as List<Object?>).cast<num>(),
          '${sample['id']} ${entry.key}',
        );
      }
    }

    for (final rawCase in source['applyCases']! as List<Object?>) {
      final sample = Map<String, Object?>.from(rawCase! as Map);
      final item = OverlayWorkspaceLayoutItem.fromMap(
        Map<String, Object?>.from(sample['item']! as Map),
      );
      final rect = (sample['rect']! as List<Object?>).cast<num>();
      final applied = OverlayWorkspaceLayoutGeometry.apply(
        item,
        Rect.fromLTWH(
          rect[0].toDouble(),
          rect[1].toDouble(),
          rect[2].toDouble(),
          rect[3].toDouble(),
        ),
      );
      final normalized = (sample['expectedNormalized']! as List<Object?>)
          .cast<num>();
      expect(applied.x, closeTo(normalized[0].toDouble(), 0.001));
      expect(applied.y, closeTo(normalized[1].toDouble(), 0.001));
      expect(applied.width, closeTo(normalized[2].toDouble(), 0.001));
      expect(applied.height, closeTo(normalized[3].toDouble(), 0.001));
      _expectRect(
        OverlayWorkspaceLayoutGeometry.resolve(applied),
        (sample['expectedResolved']! as List<Object?>).cast<num>(),
        '${sample['id']} resolved',
      );
    }

    for (final rawCase in source['eventCases']! as List<Object?>) {
      final sample = Map<String, Object?>.from(rawCase! as Map);
      _expectRect(
        OverlayWorkspaceLayoutGeometry.resolveEventNotificationRect(
          surfaceWidth: (sample['surfaceWidth']! as num).toDouble(),
          surfaceHeight: (sample['surfaceHeight']! as num).toDouble(),
          side: sample['side']! as String,
          normalizedY: (sample['normalizedY']! as num).toDouble(),
          preferredHeight: (sample['preferredHeight']! as num).toDouble(),
          snapSize: (sample['snapSize']! as num).toDouble(),
        ),
        (sample['expected']! as List<Object?>).cast<num>(),
        sample['id']! as String,
      );
    }

    for (final rawCase in source['sceneCases']! as List<Object?>) {
      final sample = Map<String, Object?>.from(rawCase! as Map);
      final actual = OverlayWorkspaceRuntimeProjection.resolveScene(
        preference: sample['preference']! as String,
        hasCurrentPartyRoom: sample['hasCurrentPartyRoom']! as bool,
      );
      expect(
        actual.kind,
        sample['expectedKind'] == 'PartyRoom'
            ? OverlayWorkspaceSceneKind.partyRoom
            : OverlayWorkspaceSceneKind.fleet,
      );
      expect(actual.isFallback, sample['expectedFallback']);
    }

    for (final rawCase in source['visibilityCases']! as List<Object?>) {
      final sample = Map<String, Object?>.from(rawCase! as Map);
      final settingValues = _completeWorkspaceSettings()
        ..addAll(Map<String, Object?>.from(sample['settings']! as Map));
      final content = Map<String, Object?>.from(sample['content']! as Map);
      final actual = OverlayWorkspaceRuntimeProjection.resolveVisibility(
        OverlayWorkspaceSettings.fromMap(settingValues),
        noticeHasContent: content['noticeHasContent']! as bool,
        chatHasContent: content['chatHasContent']! as bool,
        eventNotificationsHaveContent:
            content['eventNotificationsHaveContent']! as bool,
      );
      final expected = Map<String, Object?>.from(sample['expected']! as Map);
      expect(actual.showNotice, expected['showNotice']);
      expect(actual.showSquads, expected['showSquads']);
      expect(actual.showMembers, expected['showMembers']);
      expect(actual.showChat, expected['showChat']);
      expect(actual.showCrosshair, expected['showCrosshair']);
      expect(actual.showEventNotifications, expected['showEventNotifications']);
    }
  });

  test('workspace editor covers every active setting exactly once', () {
    final editable = OverlayWorkspaceSettings.requiredFields.difference(
      overlayWorkspaceRetiredFields,
    );
    final exposed = overlayWorkspaceFieldSpecs
        .map((field) => field.field)
        .toList(growable: false);
    expect(exposed.toSet(), editable);
    expect(exposed, hasLength(editable.length));
  });

  test('each WPF overlay module owns one clear settings entry', () {
    expect(overlayWorkspaceGroupOrder, const [
      'notice',
      'fleetOverview',
      'members',
      'chat',
      'events',
      'crosshair',
      'appearance',
      'startup',
    ]);

    final fieldsByGroup = <String, Set<String>>{
      for (final group in overlayWorkspaceGroupOrder)
        group: overlayWorkspaceFieldSpecs
            .where((spec) => spec.group == group)
            .map((spec) => spec.field)
            .toSet(),
    };

    expect(fieldsByGroup['notice'], {
      'showNotice',
      'communicationFriendEvents',
      'communicationMessagePreview',
      'communicationEventDurationSeconds',
      'fleetChatScope',
    });
    expect(fieldsByGroup['fleetOverview'], {
      'showSquads',
      'hideSquadIcons',
      'squadStatusDisplayMode',
    });
    expect(fieldsByGroup['members'], {
      'showMembers',
      'memberNameMode',
      'hideOfflineMembers',
      'hideMemberOnlineStatus',
      'hideSelfMember',
      'memberPriorityMode',
      'memberScopeMode',
      'memberNameColumnRatio',
    });
    expect(fieldsByGroup['chat']!.first, 'showChat');
    expect(fieldsByGroup['events']!.first, 'showEventNotifications');
    expect(fieldsByGroup['crosshair']!.first, 'showCrosshair');
    expect(fieldsByGroup['appearance'], contains('opacity'));
    expect(
      fieldsByGroup['startup'],
      containsAll({'enableTrayMode', 'scenePreference'}),
    );
    expect(fieldsByGroup, isNot(contains('modules')));
    expect(fieldsByGroup, isNot(contains('communication')));
    expect(fieldsByGroup, isNot(contains('squads')));

    OverlayWorkspaceFieldSpec field(String name) =>
        overlayWorkspaceFieldSpecs.singleWhere((spec) => spec.field == name);
    expect(field('showSquads').labelZh, '显示舰队总览');
    expect(field('hideSquadIcons').userVisible, isFalse);
    expect(field('squadStatusDisplayMode').userVisible, isFalse);
    expect(field('hideOfflineMembers').userVisible, isFalse);
    expect(field('memberPriorityMode').userVisible, isFalse);
    expect(field('memberScopeMode').userVisible, isFalse);
    expect(
      overlaySettingsZhCn['overlay.workspace.group.fleetOverview'],
      '舰队总览',
    );
    expect(overlaySettingsZhCn['overlay.workspace.module.Squads'], '舰队总览');
    expect(
      overlaySettingsZhCn,
      isNot(contains('overlay.workspace.group.squads')),
    );
  });

  test('single event preview separates WPF placement from visible chrome', () {
    final rect = OverlayWorkspaceLayoutGeometry.resolveEventNotificationRect(
      surfaceWidth: 1920,
      surfaceHeight: 1080,
      side: 'Right',
      normalizedY: 0.34,
      preferredHeight:
          OverlayWorkspaceLayoutGeometry.singleEventNotificationPlacementHeight,
    );
    expect(rect.width, 380);
    expect(rect.height, 90);
    expect(
      OverlayWorkspaceLayoutGeometry.singleEventNotificationPreviewHeight,
      64,
    );
  });

  testWidgets(
    'event preview is actual size fullscreen and uniformly scaled inline',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = OverlayWorkspaceSettings.fromMap(
        _completeWorkspaceSettings()..['showEventNotifications'] = true,
      );

      Widget preview(Size size) => _app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: OverlayWorkspaceFixedPreviews(
              settings: settings,
              surfaceSize: const Size(1920, 1080),
              simulate: true,
            ),
          ),
        ),
      );

      await tester.pumpWidget(preview(const Size(1920, 1080)));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('overlay-runtime-preview-event'))),
        const Size(380, 64),
      );
      final fullscreenEvent = find.byKey(
        const Key('overlay-runtime-preview-event'),
      );
      final eventText = find.descendant(
        of: fullscreenEvent,
        matching: find.byType(Text),
      );
      final eventBottom = tester.getRect(fullscreenEvent).bottom;
      var contentBottom = double.negativeInfinity;
      for (var index = 0; index < eventText.evaluate().length; index += 1) {
        final bottom = tester.getRect(eventText.at(index)).bottom;
        if (bottom > contentBottom) {
          contentBottom = bottom;
        }
      }
      expect(
        eventBottom - contentBottom,
        lessThanOrEqualTo(22),
        reason: 'A single event row must not reserve an empty lower block.',
      );

      await tester.pumpWidget(preview(const Size(960, 540)));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('overlay-runtime-preview-event'))),
        const Size(190, 32),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'workspace adapter rejects a missing setting instead of shrinking',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 10,
      )..acceptHostCapabilities(['overlay.workspace']);
      final settings = _completeWorkspaceSettings()..remove('requestedSkin');
      final layout = _workspaceLayout();
      final subscription = pair.host.incoming.listen((request) {
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 10,
              status: 'ok',
              payload: {
                'schemaVersion': 1,
                'revision': 3,
                'storageState': 'ready',
                'activePresetId': 'preset1',
                'renderMode': 'DirectComposition',
                'hotkey': {
                  'binding': 'Ctrl+Shift+O',
                  'enabled': true,
                  'runtimeState': 'unavailable',
                },
                'settings': settings,
                'layout': layout,
                'presets': [
                  {
                    'id': 'preset1',
                    'name': '默认预设',
                    'isActive': true,
                    'storageState': 'ready',
                    'settings': settings,
                    'layout': layout,
                  },
                ],
              },
            ),
          ),
        );
      });
      addTearDown(subscription.cancel);
      addTearDown(session.close);

      final result = await BridgeOverlayWorkspaceAdapter(session).read();

      expect(result.availability, OverlayWorkspaceAvailability.unavailable);
      expect(result.failure, OverlaySettingsFailure.invalidResponse);
    },
  );

  test(
    'bridge adapter sends an unsaved workspace draft without account context',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 11,
      )..acceptHostCapabilities(['overlay.runtime']);
      BridgeEnvelope? received;
      final subscription = pair.host.incoming.listen((request) {
        received = request;
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 11,
              status: 'ok',
              payload: const {
                'schemaVersion': 1,
                'windowState': 'open',
                'isVisible': true,
                'appliedRevision': 42,
                'hotkeyState': 'registered',
                'followGameState': 'followingGame',
                'requestedSkin': 'Default',
                'effectiveSkin': 'Default',
                'usedFallbackSkin': false,
                'retryable': false,
              },
            ),
          ),
        );
      });
      addTearDown(subscription.cancel);
      addTearDown(session.close);

      final workspace = _workspaceSnapshot();
      final draft = OverlayWorkspaceRuntimeDraft(
        expectedRevision: workspace.revision!,
        settings: workspace.settings!,
        layout: workspace.layout,
        hotkey: workspace.hotkey!,
      );
      final result = await BridgeOverlayWorkspaceAdapter(session)
          .executeRuntime(
            OverlayRuntimeAction.open,
            language: 'zh-CN',
            draft: draft,
          );

      expect(result.windowState, 'open');
      expect(result.isVisible, isTrue);
      expect(received?.name, 'overlay.runtime.open');
      expect(received?.payload, {
        'schemaVersion': 1,
        'language': 'zh-CN',
        'workspace': draft.toMap(),
      });
      expect(received?.accountContext, isNull);
    },
  );

  testWidgets('fullscreen shares drafts, tools and undo with the workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final window = _MemoryEditorWindow();
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
      editorWindow: window,
    );
    addTearDown(module.dispose);
    await module.initialize();
    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();
    module.workspace!.updateSetting('showMembers', true);
    await tester.pump();
    await tester.tap(find.byKey(const Key('overlay-enter-fullscreen')));
    await tester.pumpAndSettle();
    expect(window.entered, isTrue);
    expect(find.byKey(const Key('overlay-fullscreen-editor')), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.descendant(
              of: find.byKey(const Key('overlay-fullscreen-section')),
              matching: find.byType(DropdownButtonFormField<String>),
            ),
          )
          .initialValue,
      'notice',
    );
    expect(
      find.byKey(const Key('overlay-layout-horizontal-anchor-Notice')),
      findsOneWidget,
    );
    expect(module.workspace!.projection.value.settings!['showMembers'], isTrue);

    // Hiding/restoring a module only changes visibility, never its geometry.
    final before = module.workspace!.projection.value.layout[2];
    tester
        .widget<DropdownButtonFormField<String>>(
          find.descendant(
            of: find.byKey(const Key('overlay-fullscreen-section')),
            matching: find.byType(DropdownButtonFormField<String>),
          ),
        )
        .onChanged!('members');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overlay-field-showMembers')));
    await tester.pumpAndSettle();
    expect(
      module.workspace!.projection.value.settings!['showMembers'],
      isFalse,
    );
    expect(module.workspace!.projection.value.layout[2], same(before));
    await tester.tap(find.byKey(const Key('overlay-field-showMembers')));
    await tester.pumpAndSettle();

    final handle = find.byKey(const Key('overlay-editor-tools-drag'));
    final toolsBefore = tester.getTopLeft(handle);
    await tester.drag(handle, const Offset(-150, 12));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(handle).dx, lessThan(toolsBefore.dx));
    final draggedPosition = tester.getTopLeft(handle);
    await tester.tap(find.byKey(const Key('overlay-toggle-tools')));
    await tester.pumpAndSettle();
    expect(handle, findsNothing);
    await tester.tap(find.byKey(const Key('overlay-toggle-tools')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(handle), draggedPosition);
    await tester.tap(find.byKey(const Key('overlay-toggle-tools')));
    await tester.pumpAndSettle();

    final member = find.byKey(const Key('overlay-layout-module-Members'));
    await tester.drag(member, const Offset(60, 25));
    await tester.pumpAndSettle();
    final moved = module.workspace!.projection.value.layout[2];
    expect(moved.x, greaterThan(before.x));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(module.workspace!.projection.value.layout[2].x, before.x);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-fullscreen-editor')), findsNothing);
    expect(window.entered, isFalse);
    expect(module.workspace!.projection.value.dirty, isTrue);
    expect(module.workspace!.canUndo, isTrue);
    expect(module.workspace!.projection.value.settings!['showMembers'], isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fullscreen failure stays recoverable and keeps the draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final window = _MemoryEditorWindow()..failEnter = true;
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
      editorWindow: window,
    );
    addTearDown(module.dispose);
    await module.initialize();
    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();
    module.workspace!.updateSetting('showMembers', true);
    await tester.pump();
    await tester.tap(find.byKey(const Key('overlay-enter-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-fullscreen-editor')), findsNothing);
    expect(module.workspace!.projection.value.dirty, isTrue);
    window.failEnter = false;
    await tester.tap(find.byKey(const Key('overlay-enter-fullscreen')));
    await tester.pumpAndSettle();
    window.failExit = true;
    await tester.tap(find.byKey(const Key('overlay-exit-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-fullscreen-editor')), findsOneWidget);
    expect(window.entered, isTrue);
    window.failExit = false;
    await tester.tap(find.byKey(const Key('overlay-exit-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-fullscreen-editor')), findsNothing);
    expect(window.entered, isFalse);
    expect(module.workspace!.projection.value.dirty, isTrue);
  });
  test('overlay copy exists in every locale and stays user-facing', () {
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings.resolve(locale);
      for (final key in <String>[
        'overlay.title',
        'overlay.enabled',
        'overlay.opacity',
        'overlay.position.bottomRight',
        'overlay.preview.title',
        'overlay.unavailable.title',
        'overlay.retry',
        'overlay.workspace.preset',
        'overlay.workspace.save',
        'overlay.workspace.undo',
        'overlay.workspace.redo',
        'overlay.workspace.group.layout',
        'overlay.workspace.sections',
        'overlay.preview.stageTitle',
        'overlay.preview.reference',
        'overlay.preview.visibleCount',
        'overlay.preview.draft',
        'overlay.preview.saved',
        'overlay.runtime.open',
        'overlay.runtime.closed',
        'overlay.runtime.failedDescription',
        'overlay.runtime.openAction',
        'overlay.runtime.retryAction',
        'overlay.runtime.previewTitle',
        'overlay.runtime.previewDescription',
      ]) {
        expect(strings.text(key), isNot(key));
      }
      for (final group in overlayWorkspaceGroupOrder) {
        final key = 'overlay.workspace.group.$group';
        expect(strings.text(key), isNot(key));
      }
      for (final spec in overlayWorkspaceFieldSpecs) {
        final key = 'overlay.workspace.field.${spec.field}';
        expect(
          strings.text(key),
          isNot(key),
          reason: '${locale.toLanguageTag()}: $key',
        );
      }
    }
    expect(overlaySettingsZhCn.keys.toSet(), overlaySettingsZhTw.keys.toSet());
    expect(overlaySettingsZhCn.keys.toSet(), overlaySettingsEn.keys.toSet());
    for (final copy in [
      overlaySettingsZhCn,
      overlaySettingsZhTw,
      overlaySettingsEn,
    ]) {
      final visible = copy.values.join('\n');
      expect(visible, isNot(contains('Native Host')));
      expect(visible, isNot(contains('WPF')));
      expect(visible, isNot(contains('schemaVersion')));
    }
  });
  editorRegressionTests();
  editorAdditionalTests();
}

void editorRegressionTests() {
  testWidgets('fullscreen unifies module behavior, layout and decoration', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = _MemoryWorkspacePort(_workspaceSnapshot());
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: port,
      editorWindow: _MemoryEditorWindow(),
    );
    addTearDown(module.dispose);
    await module.initialize();
    final workspace = module.workspace!;
    final editor = OverlayWorkspaceEditorState()..selectedKey = 'Notice';
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _app(OverlayWorkspaceFullscreenEditor(module: workspace, editor: editor)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('overlay-fullscreen-runtime-action')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('overlay-fullscreen-section')), findsOneWidget);
    expect(find.byKey(const Key('overlay-group-notice')), findsOneWidget);
    expect(find.byKey(const Key('overlay-field-showNotice')), findsOneWidget);
    expect(
      find.byKey(const Key('overlay-layout-inspector-Notice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-editor-overall-opacity')),
      findsNothing,
    );
    expect(find.byKey(const Key('overlay-editor-text-opacity')), findsNothing);
    expect(
      find.byKey(const Key('overlay-editor-background-opacity')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('overlay-fullscreen-runtime-action')),
    );
    await tester.pumpAndSettle();
    expect(port.lastRuntimeAction, OverlayRuntimeAction.open);

    tester
        .widgetList<Slider>(
          find.descendant(
            of: find.byKey(const Key('overlay-layout-text-opacity-Notice')),
            matching: find.byType(Slider),
          ),
        )
        .single
        .onChanged!(0.72);
    await tester.pump();
    tester
        .widgetList<Slider>(
          find.descendant(
            of: find.byKey(
              const Key('overlay-layout-background-opacity-Notice'),
            ),
            matching: find.byType(Slider),
          ),
        )
        .single
        .onChanged!(0.38);
    await tester.pump();

    final notice = workspace.projection.value.layout.singleWhere(
      (item) => item.key == 'Notice',
    );
    expect(notice.textOpacity, 0.72);
    expect(notice.backgroundOpacity, 0.38);
    tester
        .widgetList<Slider>(
          find.descendant(
            of: find.byKey(
              const Key('overlay-layout-decoration-opacity-Notice'),
            ),
            matching: find.byType(Slider),
          ),
        )
        .single
        .onChanged!(0.64);
    await tester.pump();
    expect(
      workspace.projection.value.layout
          .singleWhere((item) => item.key == 'Notice')
          .decorationOpacity,
      0.64,
    );

    tester
        .widget<DropdownButtonFormField<String>>(
          find.descendant(
            of: find.byKey(const Key('overlay-fullscreen-section')),
            matching: find.byType(DropdownButtonFormField<String>),
          ),
        )
        .onChanged!('appearance');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-group-appearance')), findsOneWidget);
    expect(find.byKey(const Key('overlay-field-opacity')), findsNothing);

    tester
        .widget<DropdownButtonFormField<String>>(
          find.descendant(
            of: find.byKey(const Key('overlay-fullscreen-section')),
            matching: find.byType(DropdownButtonFormField<String>),
          ),
        )
        .onChanged!('chat');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-group-chat')), findsOneWidget);
    expect(
      find.byKey(const Key('overlay-field-chatDisplayMode')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-layout-inspector-Chat')),
      findsOneWidget,
    );
  });

  testWidgets(
    'fullscreen barrage preview replaces the message-list rectangle',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = OverlaySettingsModule(
        InMemoryOverlaySettingsAdapter(),
        workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
        editorWindow: _MemoryEditorWindow(),
      );
      addTearDown(module.dispose);
      await module.initialize();
      final workspace = module.workspace!;
      workspace.updateSetting('showChat', true);
      workspace.updateSetting('chatDisplayMode', 'FullScreenBarrage');
      workspace.updateSetting('chatShowSender', true);
      workspace.updateSetting('chatShowTimestamp', true);
      final editor = OverlayWorkspaceEditorState()..selectedKey = 'Chat';
      addTearDown(editor.dispose);

      await tester.pumpWidget(
        _app(
          OverlayWorkspaceFullscreenEditor(module: workspace, editor: editor),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('overlay-runtime-preview-barrage')),
        findsOneWidget,
      );
      expect(find.text('这是聊天弹幕'), findsWidgets);
      expect(find.text('发送者'), findsWidgets);
      expect(find.text('21:14'), findsWidgets);
      expect(find.text('NightShadow'), findsNothing);
      expect(
        find.byKey(const Key('overlay-runtime-preview-barrage-lane-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('overlay-runtime-preview-barrage-lane-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('overlay-runtime-preview-barrage-lane-2')),
        findsNothing,
      );
      final barrageLane = find.byKey(
        const Key('overlay-runtime-preview-barrage-lane-1'),
      );
      final lanePosition = tester.widget<Positioned>(barrageLane);
      final laneTexts = tester
          .widgetList<Text>(
            find.descendant(of: barrageLane, matching: find.byType(Text)),
          )
          .toList();
      double intrinsicWidth(Text text) {
        final painter = TextPainter(
          text: TextSpan(text: text.data, style: text.style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        return painter.width;
      }

      final requiredLaneWidth =
          laneTexts.fold<double>(0, (sum, text) => sum + intrinsicWidth(text)) +
          29;
      expect(lanePosition.width, greaterThanOrEqualTo(requiredLaneWidth));
      expect(
        laneTexts.singleWhere((text) => text.data == '弹幕会从右向左移动').overflow,
        isNot(TextOverflow.clip),
      );
      expect(
        tester
            .widgetList<OverlayPreviewContent>(
              find.byType(OverlayPreviewContent),
            )
            .where((preview) => preview.moduleKey == 'Chat'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'editor assistance separates snap enablement from snap distance',
    (tester) async {
      final editor = OverlayWorkspaceEditorState();
      addTearDown(editor.dispose);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SizedBox(
              width: 408,
              child: ListenableBuilder(
                listenable: editor,
                builder: (context, _) => OverlayWorkspaceEditorTools(
                  editor: editor,
                  allowSimulation: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('overlay-editor-preview-assists')), findsOne);
      expect(find.byKey(const Key('overlay-editor-grid-snap')), findsOne);
      expect(
        find.byKey(const Key('overlay-editor-layout-constraints')),
        findsOne,
      );
      expect(find.text('关闭网格吸附'), findsNothing);
      expect(find.byKey(const Key('overlay-layout-grid-16')), findsNothing);

      await tester.tap(
        find.byKey(const Key('overlay-layout-grid-snap-toggle')),
      );
      await tester.pumpAndSettle();

      expect(editor.snapToGrid, isTrue);
      expect(find.byKey(const Key('overlay-layout-grid-16')), findsOne);
      expect(find.byKey(const Key('overlay-layout-grid-32')), findsOne);
      expect(find.byKey(const Key('overlay-layout-grid-64')), findsOne);
    },
  );

  test('fixed appearances enforce the WPF palette contract', () async {
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
      editorWindow: _MemoryEditorWindow(),
    );
    addTearDown(module.dispose);
    await module.initialize();
    final workspace = module.workspace!;
    const locked = <String, (String, String)>{
      'NightShadow': ('NightShadow', 'NightShadowFlowField'),
    };

    for (final entry in locked.entries) {
      workspace.updateSetting('autoThemeByShip', true);
      workspace.updateSetting('theme', 'Default');
      workspace.updateSetting('skin', entry.key);
      var settings = workspace.projection.value.settings!;
      expect(settings['theme'], entry.value.$1, reason: entry.key);
      expect(settings['autoThemeByShip'], isFalse, reason: entry.key);
      expect(settings['startupTransitionFollowOverlayTheme'], isTrue);
      expect(settings['startupTransitionStyle'], entry.value.$2);

      workspace.updateSetting('theme', 'Drake');
      workspace.updateSetting('autoThemeByShip', true);
      settings = workspace.projection.value.settings!;
      expect(settings['theme'], entry.value.$1, reason: entry.key);
      expect(settings['autoThemeByShip'], isFalse, reason: entry.key);
    }
  });

  testWidgets('fixed appearance exposes its palette as read-only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
      editorWindow: _MemoryEditorWindow(),
    );
    addTearDown(module.dispose);
    await module.initialize();
    module.workspace!.updateSetting('skin', 'NightShadow');

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: OverlayWorkspaceSettingsGroup(
            group: 'appearance',
            fields: overlayWorkspaceFieldSpecs
                .where(
                  (field) =>
                      field.group == 'appearance' && field.field != 'skin',
                )
                .toList(),
            settings: module.workspace!.projection.value.settings!,
            onChanged: module.workspace!.updateSetting,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('overlay-field-theme')), findsNothing);
    expect(
      find.byKey(const Key('overlay-appearance-fixed-palette')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-field-autoThemeByShip')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('overlay-field-nightShadowBloom')),
      findsOneWidget,
    );
  });

  testWidgets(
    'appearance selector follows the runtime catalog and preserves the server lock',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final appearances = _workspaceAppearances()
          .map(
            (appearance) => appearance.id == 'NightShadow'
                ? appearance.copyWith(isAvailable: false)
                : appearance,
          )
          .toList(growable: false);
      final module = OverlaySettingsModule(
        InMemoryOverlaySettingsAdapter(),
        workspacePort: _MemoryWorkspacePort(
          _workspaceSnapshot(appearancesOverride: appearances),
        ),
        editorWindow: _MemoryEditorWindow(),
      );
      addTearDown(module.dispose);
      await module.initialize();

      await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('overlay-appearance-center-entry')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('overlay-appearance-specimen-Default')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('overlay-appearance-specimen-NightShadow')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('overlay-appearance-specimen-Verdict')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('overlay-appearance-card-NightShadow')),
      );
      await tester.pumpAndSettle();
      final locked = tester.widget<FilledButton>(
        find.byKey(const Key('overlay-appearance-apply-NightShadow')),
      );
      expect(locked.onPressed, isNull);

      await tester.tap(
        find.byKey(const Key('overlay-appearance-card-Verdict')),
      );
      await tester.pumpAndSettle();
      final unfinished = tester.widget<FilledButton>(
        find.byKey(const Key('overlay-appearance-apply-Verdict')),
      );
      expect(unfinished.onPressed, isNull);
      expect(
        find.byKey(const Key('overlay-appearance-preview-unavailable-Verdict')),
        findsOneWidget,
      );

      module.workspace!.updateSetting('skin', 'NightShadow');
      expect(module.workspace!.projection.value.settings!['skin'], 'Default');
      module.workspace!.updateSetting('skin', 'Verdict');
      expect(module.workspace!.projection.value.settings!['skin'], 'Default');
    },
  );

  testWidgets('preview-ready unreleased Verdict cannot be applied', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appearances = _workspaceAppearances()
        .map(
          (appearance) => appearance.id == 'Verdict'
              ? appearance.copyWith(isPreviewAvailable: true, isAvailable: true)
              : appearance,
        )
        .toList();
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(
        _workspaceSnapshot(appearancesOverride: appearances),
      ),
      editorWindow: _MemoryEditorWindow(),
    );
    addTearDown(module.dispose);
    await module.initialize();
    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overlay-appearance-center-entry')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overlay-appearance-specimen-Verdict')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('overlay-appearance-preview-unavailable-Verdict')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('overlay-appearance-card-Verdict')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('overlay-appearance-apply-Verdict')),
          )
          .onPressed,
      isNull,
    );
    module.workspace!.updateSetting('skin', 'Verdict');
    expect(module.workspace!.projection.value.settings!['skin'], 'Default');
  }, skip: !const bool.fromEnvironment('STARBRIDGE_TEST_PRIVATE_APPEARANCE'));

  testWidgets('unfinished Verdict stays locked and does not expose a preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appearances = _workspaceAppearances()
        .map(
          (appearance) => appearance.id == 'Verdict'
              ? appearance.copyWith(isAvailable: false)
              : appearance,
        )
        .toList(growable: false);
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(
        _workspaceSnapshot(appearancesOverride: appearances),
      ),
      editorWindow: _MemoryEditorWindow(),
    );
    addTearDown(module.dispose);
    await module.initialize();

    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overlay-appearance-center-entry')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('overlay-appearance-card-LagrangeWeave')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('overlay-appearance-card-Verdict')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('overlay-appearance-preview-unavailable-Verdict')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('overlay-appearance-apply-Verdict')),
          )
          .onPressed,
      isNull,
    );
    module.workspace!.updateSetting('skin', 'Verdict');
    expect(module.workspace!.projection.value.settings!['skin'], 'Default');
  });

  testWidgets(
    'released appearances use data-free overlay structure and apply their locked identity',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = _MemoryWorkspacePort(_workspaceSnapshot());
      final module = OverlaySettingsModule(
        InMemoryOverlaySettingsAdapter(),
        workspacePort: port,
        editorWindow: _MemoryEditorWindow(),
      );
      addTearDown(module.dispose);
      await module.initialize();

      await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('overlay-appearance-center-entry')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OverlayAppearancePreview), findsNWidgets(2));
      for (final id in const ['Default', 'NightShadow']) {
        final specimen = find.byKey(Key('overlay-appearance-specimen-$id'));
        expect(specimen, findsOneWidget);
        expect(
          tester
              .widgetList<Text>(
                find.descendant(of: specimen, matching: find.byType(Text)),
              )
              .map((text) => text.data),
          ['动画预览'], // Playback control only; no fabricated module content.
        );
      }
      expect(
        find.byKey(const Key('overlay-appearance-preview-unavailable-Verdict')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('overlay-appearance-card-NightShadow')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('overlay-appearance-apply-NightShadow')),
      );
      await tester.pumpAndSettle();

      final settings = module.workspace!.projection.value.settings!;
      expect(settings['skin'], 'NightShadow');
      expect(settings['theme'], 'NightShadow');
      expect(settings['autoThemeByShip'], isFalse);
      expect(settings['startupTransitionStyle'], 'NightShadowFlowField');
      expect(module.workspace!.projection.value.dirty, isTrue);
      await module.workspace!.save();
      expect(port.lastMutation?.settings?['skin'], 'NightShadow');
    },
  );

  test('Flutter workspace covers every persisted WPF display setting', () {
    final source = File(
      '../StarBridge.Core/Overlay/InformationOverlaySettings.cs',
    ).readAsStringSync();
    final recordBody = source.split(
      'public sealed record OverlayDisplaySettings(',
    )[1];
    final declaration = recordBody.substring(
      0,
      recordBody.indexOf(RegExp(r'\)\s*\{')),
    );
    final fields =
        RegExp(
          r'^\s*(?:bool|double|int|Overlay[A-Za-z]+|string)\s+([A-Za-z]+),?\s*$',
          multiLine: true,
        ).allMatches(declaration).map((match) {
          final name = match.group(1)!;
          return '${name[0].toLowerCase()}${name.substring(1)}';
        }).toSet();

    expect(fields, OverlayWorkspaceSettings.requiredFields);
    expect(
      overlayWorkspaceFieldSpecs.map((field) => field.field).toSet(),
      fields.difference(overlayWorkspaceRetiredFields),
    );
  });

  test('Flutter exposes only the controls and choices available in WPF', () {
    OverlayWorkspaceFieldSpec field(String name) =>
        overlayWorkspaceFieldSpecs.singleWhere((item) => item.field == name);

    for (final hidden in const {
      'requestedSkin',
      'startupTransitionFollowOverlayTheme',
      'eventNotificationY',
      'chatSide',
      'chatMaxVisibleCount',
      'fleetChatScope',
    }) {
      expect(field(hidden).userVisible, isFalse, reason: hidden);
    }

    expect(
      field('startupTransitionStyle').kind,
      OverlayWorkspaceFieldKind.readOnlyChoice,
    );
    expect(field('skin').selectableOptions, const [
      'Default',
      'NightShadow',
      'Verdict',
    ]);
    expect(field('theme').selectableOptions, const [
      'Default',
      'Anvil',
      'Drake',
      'Argo',
      'Musashi',
      'Mirai',
      'Crusader',
      'Aegis',
      'Rsi',
      'Origin',
      'Aopoa',
      'Esperia',
      'Gatac',
    ]);
    expect(field('chatDurationSeconds').numberOptions, const [
      6,
      8,
      12,
      16,
      20,
    ]);
    expect(field('chatBarrageFontSize').numberOptions, const [14, 16, 20, 24]);
    expect(overlayEventTypes.map((entry) => entry.$1), isNot(contains(1024)));
  });

  test('appearance-bound transition cannot be changed independently', () async {
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
      editorWindow: _MemoryEditorWindow(),
    );
    addTearDown(module.dispose);
    await module.initialize();
    final workspace = module.workspace!;

    workspace.updateSetting('skin', 'NightShadow');
    workspace.updateSetting('startupTransitionStyle', 'VerdictProtocol');
    workspace.updateSetting('startupTransitionFollowOverlayTheme', false);

    final settings = workspace.projection.value.settings!;
    expect(settings['startupTransitionStyle'], 'NightShadowFlowField');
    expect(settings['startupTransitionFollowOverlayTheme'], isTrue);
  });

  test('experience presets apply the exact WPF motion values', () async {
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
      editorWindow: _MemoryEditorWindow(),
    );
    addTearDown(module.dispose);
    await module.initialize();
    final workspace = module.workspace!;

    workspace.applyExperiencePreset('Smooth');
    expect(
      workspace.projection.value.settings!['enableStartupTransition'],
      isTrue,
    );
    expect(
      workspace.projection.value.settings!['startupTransitionFrameRate'],
      'Fps120',
    );
    expect(
      workspace.projection.value.settings!['animationFrameRate'],
      'Fps120',
    );

    workspace.applyExperiencePreset('ReducedMotion');
    expect(
      workspace.projection.value.settings!['enableStartupTransition'],
      isFalse,
    );
    expect(
      workspace.projection.value.settings!['startupTransitionFrameRate'],
      'Fps60',
    );
    expect(workspace.projection.value.settings!['animationFrameRate'], 'Fps60');

    workspace.applyExperiencePreset('Balanced');
    expect(
      workspace.projection.value.settings!['enableStartupTransition'],
      isTrue,
    );
    expect(
      workspace.projection.value.settings!['startupTransitionFrameRate'],
      'Fps60',
    );
    expect(workspace.projection.value.settings!['animationFrameRate'], 'Fps60');
  });

  testWidgets(
    'inline preview scales real structures while fullscreen remains unscaled',
    (tester) async {
      tester.view.physicalSize = const Size(2880, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = OverlaySettingsModule(
        InMemoryOverlaySettingsAdapter(),
        workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
        editorWindow: _MemoryEditorWindow(),
      );
      addTearDown(module.dispose);
      await module.initialize();
      final workspace = module.workspace!;
      for (final field in [
        'showNotice',
        'showMembers',
        'showEventNotifications',
        'showCrosshair',
      ]) {
        workspace.updateSetting(field, true);
      }
      workspace.updateSetting('crosshairSize', 96.0);
      final notice = workspace.projection.value.layout.firstWhere(
        (item) => item.key == 'Notice',
      );
      workspace.updateLayoutItem(notice.copyWith(height: 0.052));
      final editor = OverlayWorkspaceEditorState();
      addTearDown(editor.dispose);
      Widget inline() => OverlayWorkspaceLayoutWorkbench(
        layout: workspace.projection.value.layout,
        settings: workspace.projection.value.settings!,
        controller: editor,
        onChanged: (item, coalesce) =>
            workspace.updateLayoutItem(item, coalesce: coalesce),
      );
      await tester.pumpWidget(_app(SingleChildScrollView(child: inline())));
      await tester.pumpAndSettle();
      expect(editor.simulateInformation, isTrue);
      expect(find.byKey(const Key('overlay-editor-simulate')), findsNothing);
      expect(
        tester
            .widgetList<OverlayPreviewContent>(
              find.byType(OverlayPreviewContent),
            )
            .every((c) => c.simulate),
        isTrue,
      );
      final inlineBody = find.text('已接入舰队频道，等待指挥同步');
      expect(inlineBody, findsOneWidget);
      final inlineCanvas = find.byKey(const Key('overlay-layout-canvas'));
      final inlineTransform = tester
          .renderObject<RenderBox>(inlineBody)
          .getTransformTo(tester.renderObject<RenderBox>(inlineCanvas));
      expect(inlineTransform.entry(0, 0), lessThan(1));
      expect(inlineTransform.entry(1, 1), lessThan(1));
      await tester.pumpWidget(
        _app(
          OverlayWorkspaceFullscreenEditor(module: workspace, editor: editor),
        ),
      );
      await tester.pumpAndSettle();
      final canvas = find.byKey(const Key('overlay-layout-canvas'));
      expect(tester.getSize(canvas), const Size(1440, 1000));
      expect(editor.fullscreenSurfaceSize, const Size(1440, 1000));
      expect(
        tester.getSize(
          find.byKey(const Key('overlay-runtime-preview-crosshair')),
        ),
        const Size.square(96),
      );
      expect(
        tester.getSize(find.byKey(const Key('overlay-runtime-preview-event'))),
        const Size(320, 64),
      );
      final body = find.text('已接入舰队频道，等待指挥同步');
      expect(body, findsOneWidget);
      final transform = tester
          .renderObject<RenderBox>(body)
          .getTransformTo(tester.renderObject<RenderBox>(canvas));
      expect(transform.entry(0, 0), 1.0);
      expect(transform.entry(1, 1), 1.0);
      await tester.pumpWidget(_app(SingleChildScrollView(child: inline())));
      await tester.pumpAndSettle();
      expect(find.text('已接入舰队频道，等待指挥同步'), findsOneWidget);
      expect(find.byKey(const Key('overlay-editor-simulate')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('preview chrome ignores skin and theme selections', (
    tester,
  ) async {
    var settings = OverlayWorkspaceSettings.fromMap(
      _completeWorkspaceSettings(),
    );
    Future<BoxDecoration> render() async {
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 480,
              height: 120,
              child: OverlayPreviewModuleSurface(
                settings: settings,
                child: OverlayPreviewContent(
                  moduleKey: 'Notice',
                  settings: settings,
                  referenceSize: const Size(480, 120),
                  simulate: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = find
          .descendant(
            of: find.byType(OverlayPreviewModuleSurface),
            matching: find.byType(Container),
          )
          .first;
      return tester.widget<Container>(container).decoration! as BoxDecoration;
    }

    final baseline = await render();
    for (final skin in ['NightShadow', 'LagrangeWeave', 'Verdict']) {
      settings = settings.withValue('skin', skin).withValue('theme', skin);
      expect(await render(), baseline);
      expect(find.text('已接入舰队频道，等待指挥同步'), findsOneWidget);
    }
  });
  test('surface-aware geometry preserves native constraints and direct pixel moves', () {
    final item = _workspaceSnapshot().layout[2].copyWith(
      x: 0.2,
      y: 0.3,
      width: 0.3,
      height: 0.1,
      horizontalAnchor: 'Left',
      verticalAnchor: 'Top',
    );
    const wide = Size(3440, 1440);
    final rect = OverlayWorkspaceLayoutGeometry.resolve(
      item,
      surfaceSize: wide,
    );
    expect(rect, const Rect.fromLTWH(688, 432, 480, 144));
    final moved = OverlayWorkspaceLayoutGeometry.move(
      item: item,
      layout: [item],
      delta: const Offset(37, 19),
      smartSnap: false,
      surfaceSize: wide,
    );
    final movedRect = OverlayWorkspaceLayoutGeometry.resolve(
      moved,
      surfaceSize: wide,
    );
    expect(movedRect.left, closeTo(rect.left + 37, 0.001));
    expect(movedRect.top, closeTo(rect.top + 19, 0.001));
    final narrow = OverlayWorkspaceLayoutGeometry.resolve(
      item,
      surfaceSize: const Size(320, 240),
    );
    expect(narrow.right, lessThanOrEqualTo(320));
    expect(narrow.bottom, lessThanOrEqualTo(240));
    final stepped = OverlayWorkspaceLayoutGeometry.nudge(
      moved,
      'x',
      1,
      surfaceSize: wide,
    );
    expect(
      OverlayWorkspaceLayoutGeometry.resolve(stepped, surfaceSize: wide).left,
      closeTo(movedRect.left + 1, 0.001),
    );
  });
  test('notice remains docked to the top or bottom edge', () {
    final notice = _workspaceSnapshot().layout.first;
    final bottom = OverlayWorkspaceLayoutGeometry.move(
      item: notice,
      layout: [notice],
      delta: const Offset(160, 700),
      smartSnap: false,
    );
    final bottomRect = OverlayWorkspaceLayoutGeometry.resolve(bottom);
    expect(bottom.verticalAnchor, 'Bottom');
    expect(bottomRect.bottom, closeTo(1080, 0.001));

    final top = OverlayWorkspaceLayoutGeometry.move(
      item: bottom,
      layout: [bottom],
      delta: const Offset(0, -700),
      smartSnap: false,
    );
    final topRect = OverlayWorkspaceLayoutGeometry.resolve(top);
    expect(top.verticalAnchor, 'Top');
    expect(topRect.top, closeTo(0, 0.001));

    final docked = OverlayWorkspaceLayoutGeometry.dockNotice(notice, 'Bottom');
    expect(docked.verticalAnchor, 'Bottom');
    expect(
      OverlayWorkspaceLayoutGeometry.resolve(docked).bottom,
      closeTo(1080, 0.001),
    );
  });
  test('native event chrome follows the same palette as other modules', () {
    for (final name in ['Events', 'LagrangeWeave']) {
      final exported = File(
        '../StarBridge.OverlayRuntime.Windows/Rendering/OverlayCompositionHudWindow.$name.cs',
      );
      final source =
          (exported.existsSync()
                  ? exported
                  : File(
                      '../StarBridge.Desktop/OverlayCompositionHudWindow.$name.cs',
                    ))
              .readAsStringSync();
      expect(source, isNot(contains('row.AccentColor')));
      expect(source, contains('state.Palette.Title'));
    }
  });
  testWidgets(
    'simulated information is shared, switchable and never saved as data',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = _MemoryWorkspacePort(_workspaceSnapshot());
      final previewIdentity = ValueNotifier<OverlayPreviewIdentity?>(
        const OverlayPreviewIdentity(callSign: '多米诺', gameHandle: 'domino_CN'),
      );
      addTearDown(previewIdentity.dispose);
      final module = OverlaySettingsModule(
        InMemoryOverlaySettingsAdapter(),
        workspacePort: port,
        editorWindow: _MemoryEditorWindow(),
        previewIdentity: previewIdentity,
      );
      addTearDown(module.dispose);
      await module.initialize();
      final workspace = module.workspace!;
      for (final key in [
        'showNotice',
        'showSquads',
        'showMembers',
        'showChat',
        'showEventNotifications',
        'chatShowSender',
        'chatShowTimestamp',
      ]) {
        workspace.updateSetting(key, true);
      }
      workspace.updateSetting('chatMaxVisibleCount', 2);
      workspace.updateSetting('opacity', 1.0);
      workspace.updateSetting('eventNotificationBackgroundOpacity', 0.5);
      workspace.updateSetting('eventNotificationTextOpacity', 1.0);
      port.snapshot = _workspaceSnapshot(
        settingsOverride: workspace.projection.value.settings,
      );
      await workspace.save();
      final saved = jsonEncode(port.lastMutation!.toPayload(42));
      final editor = OverlayWorkspaceEditorState();
      addTearDown(editor.dispose);
      await tester.pumpWidget(
        _app(
          OverlayWorkspaceFullscreenEditor(module: workspace, editor: editor),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已接入舰队频道，等待指挥同步'), findsOneWidget);
      expect(find.text('舰队总览'), findsAtLeast(1));
      expect(find.textContaining('在线 3 / 4'), findsOneWidget);
      expect(find.textContaining('游戏中 2 / 3'), findsOneWidget);
      expect(find.text('Alpha 小队'), findsNothing);
      expect(find.text('多米诺 (domino_CN)'), findsOneWidget);
      expect(find.textContaining('NOVA-7'), findsNothing);
      expect(find.textContaining('Li)'), findsNothing);
      expect(find.text('发送者'), findsOneWidget);
      expect(find.text('NightShadow'), findsNothing);
      expect(find.text('准备完成，正在前往集合点。'), findsOneWidget);
      expect(find.text('成员上线'), findsOneWidget);
      for (final key in const ['Notice', 'Squads', 'Members', 'Chat']) {
        expect(
          find.byKey(Key('overlay-simulated-structure-$key')),
          findsOneWidget,
          reason: '$key must use the real module structure with sample data',
        );
      }
      expect(
        find.byKey(const Key('overlay-simulated-structure-Events')),
        findsOneWidget,
      );
      previewIdentity.value = const OverlayPreviewIdentity(
        callSign: '多米诺',
        gameHandle: 'Domino_CN',
      );
      await tester.pumpAndSettle();
      expect(find.text('多米诺 (Domino_CN)'), findsOneWidget);
      expect(find.text('多米诺 (domino_cn)'), findsNothing);
      expect(
        tester.widget<Text>(find.text('多米诺 (Domino_CN)')).overflow,
        isNot(TextOverflow.ellipsis),
      );
      final memberNameFit = find.ancestor(
        of: find.text('多米诺 (Domino_CN)'),
        matching: find.byType(FittedBox),
      );
      expect(
        tester
            .widgetList<FittedBox>(memberNameFit)
            .any((fitted) => fitted.fit == BoxFit.scaleDown),
        isTrue,
      );
      final surfaces = tester
          .widgetList<OverlayPreviewModuleSurface>(
            find.byType(OverlayPreviewModuleSurface),
          )
          .toList();
      expect(surfaces, hasLength(5));
      expect(
        surfaces.every(
          (s) =>
              s.settings['theme'] ==
              workspace.projection.value.settings!['theme'],
        ),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('overlay-editor-simulate')));
      await tester.pumpAndSettle();
      expect(editor.simulateInformation, isFalse);
      expect(find.text('准备完成，正在前往集合点。'), findsNothing);
      expect(workspace.projection.value.dirty, isFalse);
      expect(jsonEncode(port.lastMutation!.toPayload(42)), saved);
      await tester.tap(find.byKey(const Key('overlay-editor-simulate')));
      await tester.pumpAndSettle();
      workspace.updateSetting('hideOfflineMembers', true);
      workspace.updateSetting('chatShowSender', false);
      await tester.pumpAndSettle();
      expect(find.text('NightShadow'), findsNothing);
      await workspace.save();
      expect(
        jsonEncode(port.lastMutation!.toPayload(42)),
        isNot(contains('NightShadow')),
      );
      expect(
        jsonEncode(port.lastMutation!.toPayload(42)),
        isNot(contains('simulate')),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('fullscreen entry survives the responsive breakpoint changing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gate = Completer<void>();
    final window = _MemoryEditorWindow()..enterWait = gate;
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
      editorWindow: window,
    );
    addTearDown(module.dispose);
    await module.initialize();
    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overlay-enter-fullscreen')));
    await tester.pump();
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-fullscreen-editor')), findsOneWidget);
    expect(window.entered, isTrue);
  });
  testWidgets('live preview directly moves and resizes the selected module', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
      editorWindow: _MemoryEditorWindow(),
    );
    addTearDown(module.dispose);
    await module.initialize();
    module.workspace!.updateSetting('showMembers', true);
    await tester.pumpWidget(_app(OverlaySettingsPage(module: module)));
    await tester.pumpAndSettle();
    final before = module.workspace!.projection.value.layout[2];
    final previewMember = find.descendant(
      of: find.byKey(const Key('overlay-preview-stage')),
      matching: find.byKey(const Key('overlay-runtime-preview-Members')),
    );
    expect(previewMember, findsOneWidget);
    await tester.drag(previewMember, const Offset(50, 30));
    await tester.pumpAndSettle();
    final moved = module.workspace!.projection.value.layout[2];
    expect(
      moved.x,
      greaterThan(before.x),
      reason: 'Dragging the live preview must update the shared draft',
    );
    final resize = find.descendant(
      of: find.byKey(const Key('overlay-preview-stage')),
      matching: find.byKey(const Key('overlay-layout-resize-Members')),
    );
    expect(resize, findsOneWidget);
    await tester.drag(resize, const Offset(22, 18));
    await tester.pumpAndSettle();
    expect(
      module.workspace!.projection.value.layout[2].width,
      greaterThan(moved.width),
    );
  });

  testWidgets(
    'event reminder drags vertically and switches side across canvas center',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = OverlaySettingsModule(
        InMemoryOverlaySettingsAdapter(),
        workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
        editorWindow: _MemoryEditorWindow(),
      );
      addTearDown(module.dispose);
      await module.initialize();
      final workspace = module.workspace!;
      workspace.updateSetting('showEventNotifications', true);
      workspace.updateSetting('eventNotificationSide', 'Right');
      workspace.updateSetting('eventNotificationY', 0.2);
      final before = workspace.projection.value.settings!;
      final editor = OverlayWorkspaceEditorState();
      addTearDown(editor.dispose);
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 1200,
              child: OverlayWorkspaceInteractivePreview(
                module: workspace,
                editor: editor,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final event = find.byKey(const Key('overlay-runtime-preview-event'));
      expect(event, findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(event),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-450, 100));
      await tester.pump();
      await gesture.moveBy(const Offset(-450, 100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final changed = workspace.projection.value.settings!;
      expect(changed['eventNotificationSide'], 'Left');
      expect(
        (changed['eventNotificationY']! as num).toDouble(),
        greaterThan((before['eventNotificationY']! as num).toDouble()),
      );
      workspace.undo();
      expect(
        workspace.projection.value.settings!['eventNotificationSide'],
        before['eventNotificationSide'],
      );
      expect(
        workspace.projection.value.settings!['eventNotificationY'],
        before['eventNotificationY'],
      );
    },
  );

  testWidgets('tool dragging follows every mouse event within one frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final module = OverlaySettingsModule(
      InMemoryOverlaySettingsAdapter(),
      workspacePort: _MemoryWorkspacePort(_workspaceSnapshot()),
      editorWindow: _MemoryEditorWindow(),
    );
    addTearDown(module.dispose);
    await module.initialize();
    final editor = OverlayWorkspaceEditorState();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      _app(
        OverlayWorkspaceFullscreenEditor(
          module: module.workspace!,
          editor: editor,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handle = find.byKey(const Key('overlay-editor-tools-drag'));
    final pointerStart = tester.getCenter(handle);
    final gesture = await tester.startGesture(
      pointerStart,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    final before = tester.getTopLeft(handle);
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-5, 0));
    }
    await tester.pump();
    expect(
      tester.getTopLeft(handle).dx,
      closeTo(before.dx - 60, 0.5),
      reason: '60px mouse motion must move the tools by 60px even before the next frame',
    );
    await gesture.up();
  });
}

void editorAdditionalTests() {
  test('module reset follows shared WPF defaults and preserves appearance', () {
    final source = File(
      '../StarBridge.Core/Overlay/InformationOverlayPresets.cs',
    ).readAsStringSync();
    final payload = source
        .split('public const string DefaultLayoutPayload =')[1]
        .split(RegExp(r';\r?\n'))[0];
    final rows = RegExp(r'"([A-Za-z]+,[^";]+)').allMatches(payload);
    expect(rows.length, 4);
    for (final row in rows) {
      final parts = row.group(1)!.split(',');
      final original = _workspaceSnapshot().layout.singleWhere(
        (item) => item.key == parts[0],
      );
      final reset = OverlayWorkspaceLayoutGeometry.resetPosition(
        original,
        'preset1',
      );
      expect([
        reset.x,
        reset.y,
        reset.width,
        reset.height,
      ], parts.skip(1).take(4).map(double.parse).toList());
      expect(reset.textOpacity, original.textOpacity);
      expect(reset.horizontalAnchor, original.horizontalAnchor);
    }
  });
  testWidgets('pixel input validates, clamps and obeys the global lock', (
    tester,
  ) async {
    var item = _workspaceSnapshot().layout[2];
    var locked = false;
    late StateSetter refresh;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            refresh = setState;
            return SingleChildScrollView(
              child: OverlayWorkspaceLayoutInspector(
                item: item,
                layoutLocked: locked,
                nudgePixels: 1,
                onChanged: (value, _) => setState(() => item = value),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final x = find.descendant(
      of: find.byKey(const Key('overlay-pixels-Members-x')),
      matching: find.byType(TextField),
    );
    await tester.enterText(x, '320');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      OverlayWorkspaceLayoutGeometry.resolve(item).left,
      closeTo(320, 0.1),
    );
    await tester.enterText(x, '-1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('请输入不小于 0 的数字'), findsOneWidget);
    expect(
      OverlayWorkspaceLayoutGeometry.resolve(item).left,
      closeTo(320, 0.1),
    );
    await tester.enterText(x, '99999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      OverlayWorkspaceLayoutGeometry.resolve(item).right,
      lessThanOrEqualTo(1920),
    );
    expect(tester.widget<TextField>(x).controller!.text, isNot('99999'));
    refresh(() => locked = true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(x).enabled, isFalse);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(1440, 900), const Size(1280, 720)]) {
    testWidgets('fullscreen visual ${size.width.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(_loadPreviewFonts);
      final window = _MemoryEditorWindow();
      await window.enter();
      final port = _MemoryWorkspacePort(_workspaceSnapshot());
      final previewIdentity = ValueNotifier<OverlayPreviewIdentity?>(
        const OverlayPreviewIdentity(callSign: '多米诺', gameHandle: 'domino_CN'),
      );
      addTearDown(previewIdentity.dispose);
      final module = OverlaySettingsModule(
        InMemoryOverlaySettingsAdapter(),
        workspacePort: port,
        editorWindow: window,
        previewIdentity: previewIdentity,
      );
      addTearDown(module.dispose);
      await module.initialize();
      final editor = OverlayWorkspaceEditorState()..selectedKey = 'Members';
      addTearDown(editor.dispose);
      final workspace = module.workspace!;
      for (final item in workspace.projection.value.layout) {
        workspace.updateLayoutItem(
          OverlayWorkspaceLayoutGeometry.resetPosition(item, 'preset1'),
        );
      }
      for (final field in [
        'showNotice',
        'showSquads',
        'showMembers',
        'showChat',
        'showCrosshair',
        'showEventNotifications',
      ]) {
        workspace.updateSetting(field, true);
      }
      workspace.updateSetting('opacity', 1.0);
      workspace.updateSetting('crosshairSize', 96.0);
      workspace.updateSetting('crosshairOpacity', 1.0);
      workspace.updateSetting('eventNotificationTextOpacity', 1.0);
      workspace.updateSetting('eventNotificationBackgroundOpacity', 0.5);
      workspace.updateSetting('chatShowSender', true);
      workspace.updateSetting('chatShowTimestamp', true);
      workspace.updateSetting('chatMaxVisibleCount', 2);
      await tester.pumpWidget(
        _app(
          OverlayWorkspaceFullscreenEditor(module: workspace, editor: editor),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('overlay-runtime-preview-crosshair')),
        findsOneWidget,
      );
      if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
        await expectLater(
          find.byKey(const Key('overlay-fullscreen-editor')),
          matchesGoldenFile(
            'goldens/overlay_fullscreen_${size.width.toInt()}.png',
          ),
        );
      }
      // Saving directly from a pixel field must commit the in-progress input.
      final pixelX = find.descendant(
        of: find.byKey(const Key('overlay-pixels-Members-x')),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(pixelX);
      await tester.enterText(pixelX, '320');
      await tester.tap(find.byKey(const Key('overlay-fullscreen-save')));
      await tester.pumpAndSettle();
      expect(port.lastMutation?.kind, OverlayWorkspaceMutationKind.saveActive);
      expect(
        port.lastMutation!.layout!
            .singleWhere((item) => item.key == 'Members')
            .x,
        closeTo(320 / size.width, 0.001),
      );
    });
  }
}

Future<void> _loadPreviewFonts() async {
  for (final font in {
    'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
    'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
  }.entries) {
    await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
  }
  await (FontLoader('Microsoft JhengHei UI')..addFont(
        File('C:/Windows/Fonts/msjh.ttc')
            .readAsBytes()
            .then(ByteData.sublistView),
      ))
      .load();
}

Widget _app(Widget home) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    // Workspace interaction tests use still artwork; motion is tested separately.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: DefaultAssetBundle(
        bundle: _PublicWorkspaceAssets(),
        child: child!,
      ),
    ),
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
    home: Scaffold(body: home),
  );
}

/// Keep public layout baselines independent of a developer's optional artwork.
/// The production thumbnail handles this missing asset with its neutral icon.
final class _PublicWorkspaceAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key == 'assets/overlay-appearances/approved-board.png') {
      return Future.error(
        FlutterError('Optional appearance atlas not installed'),
      );
    }
    return rootBundle.load(key);
  }
}

void _expectRect(Rect actual, List<num> expected, String reason) {
  expect(expected, hasLength(4), reason: '$reason sample shape');
  expect(actual.left, closeTo(expected[0].toDouble(), 0.001), reason: reason);
  expect(actual.top, closeTo(expected[1].toDouble(), 0.001), reason: reason);
  expect(actual.width, closeTo(expected[2].toDouble(), 0.001), reason: reason);
  expect(actual.height, closeTo(expected[3].toDouble(), 0.001), reason: reason);
}

Map<String, Object?> _completeWorkspaceSettings() {
  final settings = <String, Object?>{
    'hideMissionWhenIdle': false,
    'showMission': false,
  };
  for (final field in overlayWorkspaceFieldSpecs) {
    settings[field.field] = switch (field.kind) {
      OverlayWorkspaceFieldKind.toggle => false,
      OverlayWorkspaceFieldKind.choice ||
      OverlayWorkspaceFieldKind.readOnlyChoice => field.options.first,
      OverlayWorkspaceFieldKind.numberChoice => field.numberOptions.first,
      OverlayWorkspaceFieldKind.number =>
        field.field == 'eventNotificationMaxVisibleCount' ||
                field.field == 'chatMaxVisibleCount'
            ? field.minimum.round()
            : field.minimum,
      OverlayWorkspaceFieldKind.color => '#FFFFFF',
      OverlayWorkspaceFieldKind.eventTypes => 0,
      OverlayWorkspaceFieldKind.eventDurations => <String, Object?>{},
    };
  }
  settings['eventNotificationDurations'] = <String, Object?>{
    'memberPresence': 0,
    'memberServer': 0,
    'sameServer': 0,
    'shipChange': 0,
    'locationChange': 0,
    'squadChange': 0,
    'commanderChange': 0,
    'onlineSummary': 0,
    'primaryServer': 0,
    'deathAndRespawn': 0,
    'localPlayReminder': 0,
  };
  return settings;
}

List<Map<String, Object?>> _workspaceLayout() => List.generate(
  4,
  (index) => <String, Object?>{
    'key': ['Notice', 'Squads', 'Members', 'Chat'][index],
    'x': index * 0.1,
    'y': index * 0.1,
    'width': 0.2,
    'height': 0.1,
    'horizontalAnchor': 'Center',
    'verticalAnchor': 'Middle',
    'isLocked': false,
    'textOpacity': 1.0,
    'backgroundOpacity': 0.5,
  },
  growable: false,
);

OverlayWorkspaceSnapshot _workspaceSnapshot({
  OverlayWorkspaceSettings? settingsOverride,
  List<OverlayWorkspaceAppearance>? appearancesOverride,
  bool includePartyPreset = false,
}) {
  final settings =
      settingsOverride ??
      OverlayWorkspaceSettings.fromMap(_completeWorkspaceSettings());
  final layout = _workspaceLayout()
      .map(OverlayWorkspaceLayoutItem.fromMap)
      .toList(growable: false);
  return OverlayWorkspaceSnapshot.available(
    revision: 42,
    storageState: 'ready',
    activePresetId: 'preset1',
    renderMode: 'DirectComposition',
    appearances: appearancesOverride ?? _workspaceAppearances(),
    hotkey: const OverlayWorkspaceHotkey(
      binding: 'Ctrl+Shift+O',
      enabled: true,
      runtimeState: 'unavailable',
    ),
    settings: settings,
    layout: layout,
    presets: [
      OverlayWorkspacePreset(
        id: 'preset1',
        name: '默认预设',
        isActive: true,
        storageState: 'ready',
        settings: settings,
        layout: layout,
      ),
      if (includePartyPreset)
        OverlayWorkspacePreset(
          id: 'preset2',
          name: '组队预设',
          isActive: false,
          storageState: 'ready',
          settings: OverlayWorkspaceSettings.fromMap({
            ...settings.toMap(),
            'scenePreference': 'PartyRoom',
          }),
          layout: layout,
        ),
    ],
  );
}

List<OverlayWorkspaceAppearance> _workspaceAppearances() =>
    _workspaceAppearanceMaps()
        .map(OverlayWorkspaceAppearance.fromMap)
        .toList(growable: false);

List<Map<String, Object?>> _workspaceAppearanceMaps() => [
  {
    'id': 'Default',
    'displayNameZh': '舰队标准',
    'displayNameEn': 'Fleet Standard',
    'summaryZh': '标准浮层',
    'summaryEn': 'Standard overlay',
    'traitsZh': ['厂商配色', '精密导轨', '高信息密度'],
    'traitsEn': ['Manufacturer colors', 'Precision rails', 'Dense information'],
    'previewSurface': '#081722',
    'previewPrimary': '#29AFFF',
    'previewSecondary': '#69CCFF',
    'locksTheme': false,
    'supportsBloom': false,
    'startupTransition': 'BridgeTerminal',
    'requiresEntitlement': false,
    'isReleased': true,
    'isAvailable': true,
  },
  {
    'id': 'NightShadow',
    'displayNameZh': '夜影',
    'displayNameEn': 'Night Shadow',
    'summaryZh': '深黑低反射界面',
    'summaryEn': 'Low-reflection black interface',
    'traitsZh': ['深黑面板', '红色脉冲', '窄边泛光'],
    'traitsEn': ['Black panels', 'Crimson pulse', 'Edge bloom'],
    'previewSurface': '#08090C',
    'previewPrimary': '#FF3045',
    'previewSecondary': '#9E1E30',
    'locksTheme': true,
    'supportsBloom': true,
    'startupTransition': 'NightShadowFlowField',
    'requiresEntitlement': true,
    'isReleased': true,
    'isAvailable': true,
  },
  {
    'id': 'LagrangeWeave',
    'displayNameZh': '拉格朗日织网',
    'displayNameEn': 'Lagrange Weave',
    'summaryZh': '旧预设兼容',
    'summaryEn': 'Legacy preset compatibility',
    'traitsZh': ['平衡点', '连接织网', '模块融合'],
    'traitsEn': ['Equilibrium points', 'Connected mesh', 'Module fusion'],
    'previewSurface': '#071215',
    'previewPrimary': '#B7FF58',
    'previewSecondary': '#48D8C8',
    'locksTheme': true,
    'supportsBloom': true,
    'startupTransition': 'LagrangeWeaveEquilibrium',
    'requiresEntitlement': false,
    'isReleased': false,
    'isAvailable': false,
  },
  {
    'id': 'Verdict',
    'displayNameZh': '裁决',
    'displayNameEn': 'Verdict',
    'summaryZh': '裁决轴界面',
    'summaryEn': 'Verdict axis interface',
    'traitsZh': ['裁决轴', '白色夹持', '判印节点'],
    'traitsEn': ['Verdict axis', 'White clamps', 'Seal nodes'],
    'previewSurface': '#080A0D',
    'previewPrimary': '#FF1917',
    'previewSecondary': '#F7F5F0',
    'locksTheme': true,
    'supportsBloom': true,
    'startupTransition': 'VerdictProtocol',
    'requiresEntitlement': true,
    'isReleased': false,
    'isAvailable': false,
  },
];

final class _MemoryEditorWindow implements OverlayEditorWindowPort {
  Completer<void>? enterWait;
  bool entered = false;
  bool failEnter = false;
  bool failExit = false;
  @override
  Future<void> enter() async {
    if (failEnter) throw StateError('enter failed');
    entered = true;
    await enterWait?.future;
  }

  @override
  Future<void> exit() async {
    if (failExit) throw StateError('exit failed');
    entered = false;
  }
}

final class _MemoryWorkspacePort implements OverlayWorkspacePort {
  _MemoryWorkspacePort(this.snapshot);

  OverlayWorkspaceSnapshot snapshot;
  int reads = 0;
  Object? readFailure;
  Completer<OverlayWorkspaceSnapshot>? pendingRead;
  OverlayWorkspaceMutation? lastMutation;
  int? lastExpectedRevision;
  OverlayRuntimeAction? lastRuntimeAction;
  String? lastRuntimeLanguage;
  OverlayWorkspaceRuntimeDraft? lastRuntimeDraft;
  OverlayRuntimeSnapshot runtime = const OverlayRuntimeSnapshot(
    windowState: 'closed',
    isVisible: false,
    appliedRevision: 42,
    hotkeyState: 'registered',
    followGameState: 'waitingForGame',
    requestedSkin: 'Default',
    effectiveSkin: 'Default',
    usedFallbackSkin: false,
  );

  @override
  Future<OverlayWorkspaceSnapshot> read() async {
    reads++;
    if (readFailure case final failure?) throw failure;
    return pendingRead?.future ?? snapshot;
  }

  @override
  Future<OverlayWorkspaceWriteResult> apply(
    OverlayWorkspaceMutation mutation, {
    required int expectedRevision,
  }) async {
    lastMutation = mutation;
    lastExpectedRevision = expectedRevision;
    return OverlayWorkspaceWriteResult.completed(snapshot);
  }

  @override
  Future<OverlayRuntimeSnapshot> executeRuntime(
    OverlayRuntimeAction action, {
    required String language,
    OverlayWorkspaceRuntimeDraft? draft,
  }) async {
    lastRuntimeAction = action;
    lastRuntimeLanguage = language;
    lastRuntimeDraft = draft;
    runtime = switch (action) {
      OverlayRuntimeAction.open ||
      OverlayRuntimeAction.retry => OverlayRuntimeSnapshot(
        windowState: 'open',
        isVisible: true,
        appliedRevision: snapshot.revision ?? 0,
        hotkeyState: 'registered',
        followGameState: 'followingGame',
        requestedSkin: 'Default',
        effectiveSkin: 'Default',
        usedFallbackSkin: false,
      ),
      OverlayRuntimeAction.close => OverlayRuntimeSnapshot(
        windowState: 'closed',
        isVisible: false,
        appliedRevision: snapshot.revision ?? 0,
        hotkeyState: 'registered',
        followGameState: 'waitingForGame',
        requestedSkin: 'Default',
        effectiveSkin: 'Default',
        usedFallbackSkin: false,
      ),
      OverlayRuntimeAction.getState => runtime,
    };
    return runtime;
  }

  @override
  Future<void> close() async {}
}
