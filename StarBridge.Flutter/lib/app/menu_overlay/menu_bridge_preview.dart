import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_bridge_dock.dart';
import 'menu_bridge_panels.dart';
import 'menu_bridge_style.dart';
import 'menu_friends_view.dart';
import 'menu_comms_view.dart';
import 'menu_bridge_workspace.dart';
import 'menu_notice_banner.dart';
import '../../platform/window/menu_notice.dart';
import 'menu_workspace_controller.dart';
import 'menu_profile_view.dart';
import 'menu_feature_view.dart';
import 'menu_local_tools.dart';
import 'menu_bridge_header.dart';
import '../../platform/window/menu_display_preferences.dart';
import '../../platform/window/menu_social_preferences.dart';
import '../../platform/window/menu_browser_preferences.dart';
import '../../platform/window/menu_image_preferences.dart';
import '../../platform/window/menu_screenshot_preferences.dart';
import '../../platform/window/menu_browser_resume.dart';
import '../../platform/window/menu_screenshot_directory.dart';
import '../../features/overlay_settings/menu_browser_resume_controller.dart';
import 'menu_overlay_theme.dart';
import 'menu_chrome_scale.dart';
import '../../platform/window/menu_window_preferences.dart';
import '../../platform/window/menu_restore_preferences.dart';
import '../../platform/window/menu_shortcut_settings.dart';
import '../../platform/window/menu_toolbar_preferences.dart';
import '../../platform/window/menu_attention.dart';
import '../localization/app_strings.dart';

/// Shared workspace presentation. Preview callers cannot acquire authority;
/// live ports are supplied only by the primary owner's current opening lease.
class MenuBridgePreview extends StatefulWidget {
  const MenuBridgePreview({
    super.key,
    required this.visible,
    required this.onDismiss,
    this.friends,
    this.onFriendsVisible,
    this.onFriendsAction,
    this.comms,
    this.onCommsVisible,
    this.onCommsAction,
    this.onCommsCompose,
    this.commsDisconnected = false,
    this.onProfileAction,
    this.profiles = const {},
    this.initialLayout,
    this.onLayoutChanged,
    this.features = const {},
    this.onFeatureVisible,
    this.onFeatureAction,
    this.localCall,
    this.localToolsController,
    this.initialSettings,
    this.onSettingsChanged,
    this.contextValues,
    this.preferencesFailed = false,
    this.shortcutSettings,
    this.browserResume,
    this.screenshotDirectory,
    this.system24Hour,
    this.attention = const MenuAttention(),
    this.notice,
    this.recoveryOverlay,
    this.startupMode = 'normal',
    this.settingsPreview = false,
  });
  final bool visible;
  final VoidCallback onDismiss;
  final MenuFriendsView? friends;
  final ValueChanged<bool>? onFriendsVisible;
  final void Function(String action, String key, String value)? onFriendsAction;
  final MenuCommsView? comms;
  final ValueChanged<bool>? onCommsVisible;
  final void Function(String, String)? onCommsAction;
  final void Function(String action, String key, String text, int revision)?
  onCommsCompose;
  final bool commsDisconnected;
  final void Function(String action, String window, String source, String key)?
  onProfileAction;
  final Map<String, MenuProfileView> profiles;
  final Object? initialLayout;
  final ValueChanged<Map<String, Object?>>? onLayoutChanged;
  final Map<String, MenuFeatureView> features;
  final void Function(String tool, bool visible)? onFeatureVisible;
  final void Function(String tool, String key, String value)? onFeatureAction;
  final MenuLocalCall? localCall;
  final MenuLocalToolsController? localToolsController;
  final Map<String, Object?>? initialSettings;
  final ValueChanged<Map<String, Object?>>? onSettingsChanged;
  final List<String>? contextValues;
  final bool preferencesFailed;
  final MenuShortcutSettingsPort? shortcutSettings;
  final MenuBrowserResumePort? browserResume;
  final MenuScreenshotDirectoryPort? screenshotDirectory;
  final bool? system24Hour;
  final MenuAttention attention;
  final MenuNotice? notice;
  final Widget? recoveryOverlay;
  final String startupMode;

  /// Presentation only; does not supply any live ports or action authority.
  final bool settingsPreview;
  @override
  State<MenuBridgePreview> createState() => _MenuBridgePreviewState();
}

class _MenuBridgePreviewState extends State<MenuBridgePreview> {
  late final MenuWorkspaceController workspace;
  bool _friendsShown = false, _commsShown = false;
  final _featuresShown = <String>{};
  String _lastChromeState = '';
  final _scope = Object();
  final _profileTargets = <String, ({String source, String key})>{};
  int _profileSerial = 0;
  bool _updatingProfiles = false;
  String? _notice;
  MenuLocalToolsController? localTools;
  MenuBrowserResumeController? _browserResume;
  Size get _initialViewport =>
      context.getInheritedWidgetOfExactType<MediaQuery>()?.data.size ??
      const Size(1200, 800);
  static Rect _initialOrganizationBounds(Size viewport) {
    final width = (viewport.width - 48).clamp(320.0, 900.0);
    final height = (viewport.height - 180).clamp(200.0, 620.0);
    // Initial placement only: never clamp a restored or manually moved window.
    return Rect.fromLTWH((viewport.width - width) / 2, 64, width, height);
  }

  List<MenuPanelSpec> get _specs => [
    if (widget.onFeatureVisible != null)
      for (final id in const ['organizations', 'rooms'])
        MenuPanelSpec(
          id: id,
          initialBounds: id == 'organizations'
              ? const Rect.fromLTWH(168, 132, 900, 620)
              : const Rect.fromLTWH(168, 132, 680, 550),
          viewportBounds: id == 'organizations'
              ? _initialOrganizationBounds
              : null,
          minimumSize: const Size(320, 200),
        ),
    if (widget.localCall != null)
      for (final id in const ['screenshot', 'image', 'browser', 'settings'])
        MenuPanelSpec(
          id: id,
          initialBounds: const Rect.fromLTWH(128, 132, 820, 560),
          minimumSize: const Size(320, 200),
        ),
    MenuPanelSpec(
      id: 'friends',
      initialBounds: const Rect.fromLTWH(28, 112, 340, 550),
      minimumSize: const Size(300, 180),
    ),
    MenuPanelSpec(
      id: 'comms',
      initialBounds: widget.comms == null
          ? const Rect.fromLTWH(408, 136, 460, 480)
          : Rect.fromLTWH(
              48,
              88,
              (_initialViewport.width - 96).clamp(320, 980),
              (_initialViewport.height - 176).clamp(240, 680),
            ),
      minimumSize: const Size(320, 180),
    ),
    for (final id in _profileTargets.keys)
      MenuPanelSpec(
        id: id,
        initialBounds: const Rect.fromLTWH(108, 132, 900, 620),
        minimumSize: const Size(360, 240),
      ),
  ];

  void _openProfile(String source, String key) {
    for (final entry in _profileTargets.entries) {
      if (entry.value == (source: source, key: key)) {
        workspace.open(entry.key);
        return;
      }
    }
    if (_profileTargets.length >= 4) {
      setState(() => _notice = '最多同时打开 4 个个人页面，请先关闭一个。');
      return;
    }
    final id = 'p${++_profileSerial}';
    _profileTargets[id] = (source: source, key: key);
    _updatingProfiles = true;
    workspace.reconcile(scope: _scope, panels: _specs);
    workspace.open(id);
    _updatingProfiles = false;
    _workspaceChanged();
    widget.onProfileAction?.call('open', id, source, key);
  }

  @override
  void initState() {
    super.initState();
    if (widget.localToolsController != null || widget.localCall != null) {
      localTools =
          widget.localToolsController ??
          MenuLocalToolsController(widget.localCall!);
      localTools!.addListener(_localChanged);
      final settings = widget.initialSettings;
      if (settings != null) {
        localTools!.display =
            MenuDisplayPreferences.fromSettings(settings) ??
            const MenuDisplayPreferences();
        localTools!.dimming = (settings['dimming'] as num).toDouble();
        localTools!.social = MenuSocialPreferences.fromSettings(settings)!;
        localTools!.restore = MenuRestorePreferences.fromSettings(settings)!;
        localTools!.browser = MenuBrowserPreferences.fromSettings(settings)!;
        localTools!.imagePreferences = MenuImagePreferences.fromSettings(
          settings,
        )!;
        localTools!.screenshotPreferences =
            MenuScreenshotPreferences.fromSettings(settings)!;
        localTools!.snapWindows = settings['snapWindows'] == true;
        localTools!.toolbar =
            MenuToolbarPreferences.parse(settings['toolbar']) ??
            const MenuToolbarPreferences();
      }
    }
    workspace = MenuWorkspaceController(scope: _scope, panels: _specs);
    workspace.snapWindows = localTools?.snapWindows ?? false;
    workspace.restoreLastFocus = localTools?.restore.lastFocus ?? true;
    if (widget.initialLayout != null) {
      workspace.restoreLayout(
        widget.initialLayout,
        lease: workspace.captureLayoutLease(),
        reopenPanels:
            widget.startupMode == 'normal' &&
            (localTools?.restore.remembersWindows ?? false),
      );
    }
    workspace.setVisible(widget.visible);
    workspace.addListener(_workspaceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _workspaceChanged();
    });
  }

  void _workspaceChanged() {
    if (_updatingProfiles) return;
    for (final id in _profileTargets.keys.toList()) {
      if (!workspace.isOpen(id)) {
        final target = _profileTargets.remove(id)!;
        widget.onProfileAction?.call('close', id, target.source, target.key);
        _notice = null;
      }
    }
    final friends = workspace.panelsVisible && workspace.isOpen('friends');
    for (final id in const ['organizations', 'rooms', 'hud']) {
      final shown = id == 'hud'
          ? widget.visible
          : workspace.panelsVisible && workspace.isOpen(id);
      if (shown != _featuresShown.contains(id)) {
        shown ? _featuresShown.add(id) : _featuresShown.remove(id);
        widget.onFeatureVisible?.call(id, shown);
      }
    }
    final comms = workspace.panelsVisible && workspace.isOpen('comms');
    if (friends != _friendsShown) {
      _friendsShown = friends;
      widget.onFriendsVisible?.call(friends);
    }
    if (comms != _commsShown) {
      _commsShown = comms;
      widget.onCommsVisible?.call(comms);
    }
    // Only registered tool kinds leave the desktop, never business targets.
    final layout = workspace.exportLayout();
    widget.onLayoutChanged?.call({
      ...layout,
      'panels': (layout['panels'] as List)
          .where(
            (p) => const [
              'friends',
              'comms',
              'organizations',
              'rooms',
              'hud',
              'screenshot',
              'image',
              'browser',
              'settings',
            ].contains(p['id']),
          )
          .toList(),
      'open': localTools?.restore.remembersWindows == true
          ? (layout['open'] as List)
                .where(MenuWindowPreferences.panelIds.contains)
                .toList()
          : <String>[],
    });
    final chromeState =
        '${workspace.visible}:${workspace.panelsHidden}:${workspace.activeId}:${workspace.openPanels.map((p) => p.id).join(',')}';
    if (_lastChromeState != chromeState) {
      _lastChromeState = chromeState;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _browserResume?.dispose();
    localTools?.removeListener(_localChanged);
    if (widget.localToolsController == null) localTools?.dispose();
    workspace.removeListener(_workspaceChanged);
    workspace.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MenuBridgePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.browserResume != widget.browserResume) {
      _browserResume?.dispose();
      _browserResume = null;
    }
    if (widget.visible != oldWidget.visible) {
      workspace.setVisible(
        widget.visible,
        retainPanels: localTools?.restoreDesktop ?? false,
      );
    }
  }

  void toggle(BridgePreviewPanel panel) {
    if (panel == BridgePreviewPanel.hud) {
      if (!widget.settingsPreview &&
          widget.visible &&
          !(widget.features['hud']?.busy ?? false)) {
        widget.onFeatureAction?.call('hud', 'toggle', '');
      }
      return;
    }
    final wasOpen = workspace.isOpen(panel.name);
    workspace.open(panel.name);
    final size = MediaQuery.sizeOf(context);
    final rect = workspace.boundsFor(panel.name, size);
    if (!(Offset.zero & size).overlaps(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 36),
    )) {
      workspace.recover(panel.name, size);
    }
    if (panel == BridgePreviewPanel.screenshot &&
        !wasOpen &&
        localTools?.screenshot == null) {
      unawaited(localTools?.image(capture: true));
    }
  }

  void _localChanged() {
    if (localTools case final tools?) {
      workspace.snapWindows = tools.snapWindows;
      workspace.restoreLastFocus = tools.restore.lastFocus;
      widget.onSettingsChanged?.call({
        ...tools.display.toSettingsPatch(),
        ...tools.social.toSettingsPatch(),
        'dimming': tools.dimming,
        ...tools.restore.toSettingsPatch(),
        'snapWindows': tools.snapWindows,
        'toolbar': tools.toolbar.toMap(),
        ...tools.browser.toSettingsPatch(),
        ...tools.imagePreferences.toSettingsPatch(),
        ...tools.screenshotPreferences.toSettingsPatch(),
      });
      _workspaceChanged();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.expand();
    return MenuPresentation(
      highContrast: localTools?.display.highContrast ?? false,
      tooltipDelayMilliseconds:
          localTools?.display.tooltipDelayMilliseconds ?? 500,
      reduceMotion: localTools?.display.reduceMotion ?? false,
      textScalePercent: localTools?.display.textScalePercent ?? 100,
      safeMode: widget.startupMode == 'safe',
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
        },
        child: Focus(
          autofocus: true,
          child: Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'Source Sans 3',
                fontFamilyFallback: ['Source Han Sans CN'],
                color: BridgeInk.text,
                fontSize: 15,
                height: 1.4,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    excluding: widget.recoveryOverlay != null,
                    child: IgnorePointer(
                      ignoring: widget.recoveryOverlay != null,
                      child: ExcludeFocus(
                        excluding: widget.recoveryOverlay != null,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              key: const ValueKey('menu-game-scrim'),
                              color: localTools == null
                                  ? BridgeInk.scrim
                                  : BridgeInk.scrim.withValues(
                                      alpha: localTools!.dimming,
                                    ),
                            ),
                            RepaintBoundary(
                              key: const ValueKey('menu-chrome-paint-boundary'),
                              child: MenuChromeScale(
                                percent:
                                    localTools?.display.interfaceScalePercent ??
                                    0,
                                child: SafeArea(
                                  child: LayoutBuilder(
                                    builder: (context, bounds) {
                                      final largeText =
                                          MediaQuery.textScalerOf(context)
                                              .scale(14) >
                                          21;
                                      final contextStrip = BridgeContextPreview(
                                        live: widget.friends != null,
                                        values: widget.contextValues,
                                        preferences:
                                            localTools?.display ??
                                            const MenuDisplayPreferences(),
                                      );
                                      return Padding(
                                        padding: EdgeInsets.all(
                                          !largeText && bounds.maxWidth >= 1100
                                              ? 28
                                              : 16,
                                        ),
                                        child: Column(
                                          children: [
                                            MenuBridgeHeader(
                                              windowsHidden:
                                                  workspace.panelsHidden,
                                              onToggleWindows:
                                                  workspace.openPanels.isEmpty
                                                  ? null
                                                  : workspace
                                                        .togglePanelsVisibility,
                                              onDismiss: widget.onDismiss,
                                              system24Hour: widget.system24Hour,
                                              display:
                                                  localTools?.display ??
                                                  const MenuDisplayPreferences(),
                                              presenceKey:
                                                  widget.contextValues !=
                                                          null &&
                                                      widget
                                                              .contextValues!
                                                              .length >
                                                          5
                                                  ? widget.contextValues![5]
                                                  : 'presence.unknown',
                                              onSettings: localTools == null
                                                  ? null
                                                  : () {
                                                      workspace.recover(
                                                        'settings',
                                                        MediaQuery.sizeOf(
                                                          context,
                                                        ),
                                                      );
                                                    },
                                              onHud:
                                                  widget.onFeatureVisible ==
                                                      null
                                                  ? (widget.settingsPreview
                                                        ? () {}
                                                        : null)
                                                  : () => toggle(
                                                      BridgePreviewPanel.hud,
                                                    ),
                                              hudEnabled: widget
                                                  .features['hud']
                                                  ?.hudEnabled,
                                              hudBusy:
                                                  widget
                                                      .features['hud']
                                                      ?.busy ??
                                                  false,
                                            ),
                                            if (_notice != null)
                                              BridgeCaption(_notice!),
                                            if (!widget.settingsPreview &&
                                                widget.onFeatureVisible !=
                                                    null &&
                                                (widget
                                                        .features['hud']
                                                        ?.notice
                                                        .isNotEmpty ??
                                                    false))
                                              Semantics(
                                                liveRegion: true,
                                                child: BridgeCaption(
                                                  widget
                                                      .features['hud']!
                                                      .notice,
                                                  key: const ValueKey(
                                                    'menu-hud-notice',
                                                  ),
                                                ),
                                              ),
                                            if (widget.startupMode != 'normal')
                                              BridgeCaption(
                                                AppStrings.of(context).text(
                                                  'menu.startup.${widget.startupMode}',
                                                ),
                                                key: const Key(
                                                  'menu-startup-status',
                                                ),
                                              ),
                                            if (widget.preferencesFailed)
                                              const BridgeCaption(
                                                '菜单设置未保存或未读取成功；本次调整仅在当前运行中生效。',
                                              ),
                                            const SizedBox(height: 22),
                                            const Spacer(),
                                            const SizedBox(height: 16),
                                            if (localTools
                                                    ?.display
                                                    .hasContext ??
                                                true)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 10,
                                                ),
                                                child: Center(
                                                  child: ConstrainedBox(
                                                    constraints:
                                                        const BoxConstraints(
                                                          maxWidth: 980,
                                                        ),
                                                    child: largeText
                                                        ? SingleChildScrollView(
                                                            scrollDirection:
                                                                Axis.horizontal,
                                                            child: contextStrip,
                                                          )
                                                        : contextStrip,
                                                  ),
                                                ),
                                              ),
                                            BridgePreviewDock(
                                              attention: widget.attention,
                                              preferences:
                                                  localTools?.toolbar ??
                                                  const MenuToolbarPreferences(),
                                              localToolsEnabled:
                                                  localTools != null,
                                              featuresEnabled:
                                                  widget.settingsPreview ||
                                                  widget.onFeatureVisible !=
                                                      null,
                                              selected: switch (workspace
                                                  .activeId) {
                                                'friends' =>
                                                  BridgePreviewPanel.friends,
                                                'comms' =>
                                                  BridgePreviewPanel.comms,
                                                'organizations' =>
                                                  BridgePreviewPanel
                                                      .organizations,
                                                'rooms' =>
                                                  BridgePreviewPanel.rooms,
                                                'hud' => BridgePreviewPanel.hud,
                                                'screenshot' =>
                                                  BridgePreviewPanel.screenshot,
                                                'image' =>
                                                  BridgePreviewPanel.image,
                                                'browser' =>
                                                  BridgePreviewPanel.browser,
                                                _ => null,
                                              },
                                              openPanels: {
                                                if (widget
                                                        .features['hud']
                                                        ?.hudEnabled ==
                                                    true)
                                                  BridgePreviewPanel.hud,
                                                for (final panel
                                                    in BridgePreviewPanel
                                                        .values)
                                                  if (panel !=
                                                          BridgePreviewPanel
                                                              .hud &&
                                                      workspace.isOpen(
                                                        panel.name,
                                                      ))
                                                    panel,
                                              },
                                              onToggle: toggle,
                                              hudBusy:
                                                  widget
                                                      .features['hud']
                                                      ?.busy ??
                                                  false,
                                              onRecover: (panel) =>
                                                  workspace.recover(
                                                    panel.name,
                                                    MediaQuery.sizeOf(context),
                                                  ),
                                            ),
                                            const SizedBox(height: 12),
                                            BridgeCaption(
                                              widget.friends == null &&
                                                      !widget.settingsPreview
                                                  ? '视觉预览 · 好友与通讯可展开 · 演示数据'
                                                  : AppStrings.of(context).text(
                                                      'overlay.sections.menu',
                                                    ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            // Desktop chrome is behind every floating window, including
                            // hit testing. Empty workspace space still reaches the dock.
                            MenuBridgeWorkspace(
                              safeMode: widget.startupMode == 'safe',
                              controller: workspace,
                              shortcutSettings: widget.shortcutSettings,
                              screenshotDirectory: widget.screenshotDirectory,
                              browserResume: widget.browserResume == null
                                  ? null
                                  : (_browserResume ??=
                                        MenuBrowserResumeController(
                                          widget.browserResume!,
                                        )),
                              localTools: localTools,
                              features: widget.features,
                              onFeatureAction: widget.onFeatureAction,
                              friends: widget.friends,
                              onFriendsAction: widget.onFriendsAction,
                              comms: widget.comms,
                              onCommsAction: widget.onCommsAction,
                              onCommsCompose: widget.onCommsCompose,
                              commsDisconnected: widget.commsDisconnected,
                              onProfile: widget.onProfileAction == null
                                  ? null
                                  : _openProfile,
                              profiles: {
                                for (final id in _profileTargets.keys)
                                  id:
                                      widget.profiles[id] ??
                                      const MenuProfileView('loading'),
                              },
                              onRefresh: (id) => widget.onProfileAction?.call(
                                'refresh',
                                id,
                                '',
                                '',
                              ),
                            ),
                            if (widget.notice case final notice?)
                              PositionedDirectional(
                                top: 64,
                                end: 16,
                                width: (MediaQuery.sizeOf(context).width - 32)
                                    .clamp(0, 360),
                                child: MenuNoticeBanner(notice: notice),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (widget.recoveryOverlay != null) widget.recoveryOverlay!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
