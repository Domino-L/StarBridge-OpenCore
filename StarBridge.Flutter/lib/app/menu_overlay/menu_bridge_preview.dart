import 'menu_overlay_locale.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_bridge_dock.dart';
import 'menu_bridge_panel_specs.dart';
import 'menu_panel_recovery_identity.dart';
import 'menu_bridge_panels.dart';
import 'menu_bridge_style.dart';
import 'menu_friends_view.dart';
import 'menu_comms_view.dart';
import 'menu_bridge_workspace.dart';
import 'menu_hud_quick_panel.dart';
import 'menu_hud_menu_hooks.dart';
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
import '../../platform/window/menu_desktop_widgets.dart';
import '../../platform/window/menu_exec_hangar_summary.dart';
import 'menu_exec_hangar_widget.dart';

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
    this.hangar,
    this.hangarInitial,
    this.onHangarSnapshot,
    this.onOpenHangar,
    this.hangarOpenFailed = false,
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
  final MenuExecHangarSummaryPort? hangar;
  final MenuExecHangarSummary? hangarInitial;
  final ValueChanged<MenuExecHangarSummary>? onHangarSnapshot;
  final VoidCallback? onOpenHangar;
  final bool hangarOpenFailed;
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
  MenuDesktopWidgets _desktopWidgets = const MenuDesktopWidgets();
  bool _editingWidgets = false;
  Size get _initialViewport =>
      context.getInheritedWidgetOfExactType<MediaQuery>()?.data.size ??
      const Size(1200, 800);
  List<MenuPanelSpec> get _specs => menuBridgePanelSpecs(
    hasHangar: widget.hangar != null,
    hasLocalTools: widget.localCall != null,
    profileIds: _profileTargets.keys,
    hudPanel: widget.onFeatureVisible != null ? menuHudPanelSpec() : null,
    commsViewport: widget.comms == null ? null : _initialViewport,
  );

  void _openProfile(String source, String key) {
    for (final entry in _profileTargets.entries) {
      if (entry.value == (source: source, key: key)) {
        workspace.open(entry.key);
        return;
      }
    }
    if (_profileTargets.length >= 4) {
      setState(
        () => _notice = menuText(context, 'menu.overlay.window.profileLimit'),
      );
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
    _desktopWidgets =
        MenuDesktopWidgets.parse(widget.initialSettings?['widgets']) ??
        const MenuDesktopWidgets();
    if (widget.localToolsController != null || widget.localCall != null) {
      localTools =
          widget.localToolsController ??
          MenuLocalToolsController(
            widget.localCall!,
            locale: () => Localizations.localeOf(context),
          );
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
              'execHangar',
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
    if (widget.settingsPreview &&
        oldWidget.initialSettings != widget.initialSettings) {
      _desktopWidgets =
          MenuDesktopWidgets.parse(widget.initialSettings?['widgets']) ??
          const MenuDesktopWidgets();
    }
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
    if (panel == BridgePreviewPanel.hud && widget.settingsPreview) return;
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
        'widgets': _desktopWidgets.toMap(),
      });
      _workspaceChanged();
    }
    if (mounted) setState(() {});
  }

  void _changeWidgets(MenuDesktopWidgets value, bool persist) {
    setState(() => _desktopWidgets = value);
    if (persist) _localChanged();
  }

  void _pinHangar(bool value) {
    _changeWidgets(_desktopWidgets.copyWith(hangar: value), true);
    if (value) workspace.close('execHangar');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.expand();
    if (menuHudPlacementFor(widget) case final placing?) {
      return MenuPresentation(
        safeMode: widget.startupMode == 'safe',
        reduceMotion: localTools?.display.reduceMotion ?? false,
        child: placing,
      );
    }
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
                            MenuHudScrim(
                              scrimKey: const ValueKey('menu-game-scrim'),
                              quick: workspace.isOpen('hud')
                                  ? widget.features['hud']?.hudQuick
                                  : null,
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
                                              desktopWidget:
                                                  _desktopWidgets.hangar &&
                                                      widget.hangar != null
                                                  ? MenuExecHangarWidget(
                                                      port: widget.hangar!,
                                                      preferences:
                                                          _desktopWidgets,
                                                      initial:
                                                          widget.hangarInitial,
                                                      onSnapshot: widget
                                                          .onHangarSnapshot,
                                                      editing: _editingWidgets,
                                                      onOpen: () => toggle(
                                                        BridgePreviewPanel
                                                            .execHangar,
                                                      ),
                                                      onEdit: () => setState(
                                                        () => _editingWidgets =
                                                            true,
                                                      ),
                                                      onChanged: _changeWidgets,
                                                    )
                                                  : null,
                                              onAddHangar:
                                                  widget.hangar == null ||
                                                      _desktopWidgets.hangar
                                                  ? null
                                                  : () => _pinHangar(true),
                                              editingWidgets: _editingWidgets,
                                              onEditWidgets:
                                                  widget.hangar == null
                                                  ? null
                                                  : () => setState(
                                                      () => _editingWidgets =
                                                          !_editingWidgets,
                                                    ),
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
                                                  : () => menuHudToggle(widget),
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
                                            if (widget.hangarOpenFailed)
                                              BridgeCaption(
                                                AppStrings.of(context).text(
                                                  'execHangar.widgetOpenFailed',
                                                ),
                                              ),
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
                                              BridgeCaption(
                                                menuText(
                                                  context,
                                                  'menu.overlay.window.settingsTemporary',
                                                ),
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
                                              execHangarEnabled:
                                                  widget.hangar != null,
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
                                                'execHangar' =>
                                                  BridgePreviewPanel.execHangar,
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
                                              recoveryIdentities:
                                                  menuPanelRecoveryIdentities(
                                                    workspace.openPanels,
                                                  ),
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
                                                  ? menuText(
                                                      context,
                                                      'menu.overlay.window.preview',
                                                    )
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
                            MenuBridgeWorkspace(
                              hangar: widget.hangar,
                              hangarInitial: widget.hangarInitial,
                              onHangarSnapshot: widget.onHangarSnapshot,
                              hangarPinned: _desktopWidgets.hangar,
                              onHangarPinned: _pinHangar,
                              onHangarSettings: widget.onOpenHangar,
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
