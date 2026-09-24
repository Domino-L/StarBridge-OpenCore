import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_bridge_dock.dart';
import 'menu_bridge_panels.dart';
import 'menu_bridge_style.dart';
import 'menu_friends_view.dart';
import 'menu_comms_view.dart';
import 'menu_comms_panel.dart';
import 'menu_overlay_workspace.dart';
import 'menu_workspace_controller.dart';
import 'menu_profile_view.dart';
import 'menu_feature_view.dart';
import 'menu_organizations_panel.dart';
import 'menu_local_tools.dart';
import 'menu_clock.dart';
import 'menu_overlay_theme.dart';
import '../composition/menu_profile_page.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../platform/window/menu_window_preferences.dart';

/// Explicit visual preview only. Never bootstraps an account or social adapter.
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
    this.initialSettings,
    this.onSettingsChanged,
    this.contextValues,
    this.preferencesFailed = false,
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
  final Map<String, Object?>? initialSettings;
  final ValueChanged<Map<String, Object?>>? onSettingsChanged;
  final List<String>? contextValues;
  final bool preferencesFailed;
  @override
  State<MenuBridgePreview> createState() => _MenuBridgePreviewState();
}

class _MenuBridgePreviewState extends State<MenuBridgePreview> {
  late final MenuWorkspaceController workspace;
  bool _friendsShown = false, _commsShown = false;
  String _commsChannel = 'private';
  void _selectCommsChannel(String value) {
    if (!const {'private', 'organizationChat'}.contains(value)) {
      return;
    }
    setState(() => _commsChannel = value);
    _workspaceChanged();
  }

  final _featuresShown = <String>{};
  String _lastChromeState = '';
  final _scope = Object();
  final _profileTargets = <String, ({String source, String key})>{};
  int _profileSerial = 0;
  bool _updatingProfiles = false;
  String? _notice;
  MenuLocalToolsController? localTools;
  Size get _initialViewport =>
      context.getInheritedWidgetOfExactType<MediaQuery>()?.data.size ??
      const Size(1200, 800);
  List<MenuPanelSpec> get _specs => [
    if (widget.onFeatureVisible != null)
      for (final id in const ['organizations', 'rooms', 'hud'])
        MenuPanelSpec(
          id: id,
          initialBounds: id == 'organizations'
              ? const Rect.fromLTWH(168, 132, 900, 620)
              : const Rect.fromLTWH(168, 132, 680, 550),
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
    if (widget.localCall != null) {
      localTools = MenuLocalToolsController(widget.localCall!)
        ..addListener(_localChanged);
      final settings = widget.initialSettings;
      if (settings != null) {
        localTools!.showClock = settings['showClock'] == true;
        localTools!.showContext = settings['showContext'] == true;
        localTools!.dimming = (settings['dimming'] as num).toDouble();
        localTools!.restoreDesktop = settings['restoreDesktop'] == true;
        localTools!.snapWindows = settings['snapWindows'] == true;
      }
    }
    workspace = MenuWorkspaceController(scope: _scope, panels: _specs);
    workspace.snapWindows = localTools?.snapWindows ?? false;
    if (widget.initialLayout != null) {
      workspace.restoreLayout(
        widget.initialLayout,
        lease: workspace.captureLayoutLease(),
        reopenPanels: localTools?.restoreDesktop ?? false,
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
    final friends = widget.visible && workspace.isOpen('friends');
    for (final id in const [
      'organizations',
      'rooms',
      'hud',
      'organizationChat',
    ]) {
      final shown =
          widget.visible &&
          (workspace.isOpen(id) ||
              (workspace.isOpen('comms') && id == 'organizationChat'));
      if (shown != _featuresShown.contains(id)) {
        shown ? _featuresShown.add(id) : _featuresShown.remove(id);
        widget.onFeatureVisible?.call(id, shown);
      }
    }
    final comms = widget.visible && workspace.isOpen('comms');
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
      'open': localTools?.restoreDesktop == true
          ? (layout['open'] as List)
                .where(MenuWindowPreferences.panelIds.contains)
                .toList()
          : <String>[],
    });
    final chromeState =
        '${workspace.visible}:${workspace.activeId}:${workspace.openPanels.map((p) => p.id).join(',')}';
    if (_lastChromeState != chromeState) {
      _lastChromeState = chromeState;
      setState(() {});
    }
  }

  @override
  void dispose() {
    localTools?.removeListener(_localChanged);
    localTools?.dispose();
    workspace.removeListener(_workspaceChanged);
    workspace.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MenuBridgePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      workspace.setVisible(
        widget.visible,
        retainPanels: localTools?.restoreDesktop ?? false,
      );
    }
  }

  void toggle(BridgePreviewPanel panel) {
    final wasOpen = workspace.isOpen(panel.name);
    workspace.open(panel.name);
    final size = MediaQuery.sizeOf(context);
    final rect = workspace.boundsFor(panel.name, size);
    if (!(Offset.zero & size).overlaps(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 36),
    )) {
      workspace.recover(panel.name, size);
    }
    if (panel == BridgePreviewPanel.screenshot && !wasOpen) {
      unawaited(localTools?.image(capture: true));
    }
  }

  void _localChanged() {
    if (localTools case final tools?) {
      workspace.snapWindows = tools.snapWindows;
      widget.onSettingsChanged?.call({
        'showClock': tools.showClock,
        'showContext': tools.showContext,
        'dimming': tools.dimming,
        'restoreDesktop': tools.restoreDesktop,
        'snapWindows': tools.snapWindows,
      });
      _workspaceChanged();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.expand();
    return Theme(
      data: buildMenuOverlayTheme(Localizations.localeOf(context)),
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
                  ColoredBox(
                    key: const ValueKey('menu-game-scrim'),
                    color: localTools == null
                        ? BridgeInk.scrim
                        : BridgeInk.scrim.withValues(
                            alpha: localTools!.dimming,
                          ),
                  ),
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        final largeText =
                            MediaQuery.textScalerOf(context).scale(14) > 21;
                        final contextStrip = BridgeContextPreview(
                          live: widget.friends != null,
                          values: widget.contextValues,
                        );
                        return Padding(
                          padding: EdgeInsets.all(
                            bounds.maxWidth >= 1100 ? 28 : 16,
                          ),
                          child: Column(
                            children: [
                              _Header(
                                onDismiss: widget.onDismiss,
                                showClock: localTools?.showClock ?? true,
                                onSettings: localTools == null
                                    ? null
                                    : () {
                                        workspace.recover(
                                          'settings',
                                          MediaQuery.sizeOf(context),
                                        );
                                      },
                                onHud: widget.onFeatureVisible == null
                                    ? null
                                    : () => workspace.open('hud'),
                              ),
                              if (_notice != null) BridgeCaption(_notice!),
                              if (widget.preferencesFailed)
                                const BridgeCaption(
                                  '菜单设置未保存或未读取成功；本次调整仅在当前运行中生效。',
                                ),
                              const SizedBox(height: 22),
                              const Spacer(),
                              const SizedBox(height: 16),
                              if (localTools?.showContext ?? true)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 980,
                                      ),
                                      child: largeText
                                          ? SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: contextStrip,
                                            )
                                          : contextStrip,
                                    ),
                                  ),
                                ),
                              BridgePreviewDock(
                                localToolsEnabled: localTools != null,
                                featuresEnabled:
                                    widget.onFeatureVisible != null,
                                selected: switch (workspace.activeId) {
                                  'friends' => BridgePreviewPanel.friends,
                                  'comms' => BridgePreviewPanel.comms,
                                  'organizations' =>
                                    BridgePreviewPanel.organizations,
                                  'rooms' => BridgePreviewPanel.rooms,
                                  'hud' => BridgePreviewPanel.hud,
                                  'screenshot' => BridgePreviewPanel.screenshot,
                                  'image' => BridgePreviewPanel.image,
                                  'browser' => BridgePreviewPanel.browser,
                                  _ => null,
                                },
                                openPanels: {
                                  for (final panel in BridgePreviewPanel.values)
                                    if (workspace.isOpen(panel.name)) panel,
                                },
                                onToggle: toggle,
                                onRecover: (panel) => workspace.recover(
                                  panel.name,
                                  MediaQuery.sizeOf(context),
                                ),
                              ),
                              const SizedBox(height: 12),
                              BridgeCaption(
                                widget.friends == null
                                    ? '视觉预览 · 好友与通讯可展开 · 演示数据'
                                    : widget.comms == null
                                    ? '好友只读试用 · 其他功能尚未接入'
                                    : '菜单浮层 · 本机试用',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // Desktop chrome is behind every floating window, including
                  // hit testing. Empty workspace space still reaches the dock.
                  _Workspace(
                    controller: workspace,
                    localTools: localTools,
                    features: widget.features,
                    onFeatureAction: widget.onFeatureAction,
                    friends: widget.friends,
                    onFriendsAction: widget.onFriendsAction,
                    comms: widget.comms,
                    commsChannel: _commsChannel,
                    onCommsChannel: _selectCommsChannel,
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
                    onRefresh: (id) =>
                        widget.onProfileAction?.call('refresh', id, '', ''),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onDismiss,
    this.onSettings,
    this.onHud,
    this.showClock = true,
  });
  final VoidCallback onDismiss;
  final VoidCallback? onSettings, onHud;
  final bool showClock;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final actions = Wrap(
        spacing: 18,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          BridgeMenuAction(
            label: '设置',
            onPressed: onSettings,
            child: const BridgeLabel(MenuGlyph.settings, '设置'),
          ),
          BridgeMenuAction(
            label: '打开信息浮层',
            onPressed: onHud,
            child: const BridgeLabel(MenuGlyph.overlay, '打开信息浮层'),
          ),
          BridgeMenuAction(
            key: const ValueKey('menu-return'),
            label: '返回游戏',
            onPressed: onDismiss,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('返回游戏'),
                SizedBox(width: 16),
                BridgeCaption('ESC'),
              ],
            ),
          ),
        ],
      );
      if (bounds.maxWidth < 800 ||
          MediaQuery.textScalerOf(context).scale(14) > 21) {
        // Preserve readable controls without consuming the entire tool area
        // when accessibility text is large. No text scaling override.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (showClock) const MenuClock(),
              const SizedBox(width: 24),
              actions,
            ],
          ),
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (showClock) const MenuClock() else const SizedBox.shrink(),
          actions,
        ],
      );
    },
  );
}

class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.controller,
    this.friends,
    this.onFriendsAction,
    this.comms,
    this.commsChannel = 'private',
    this.onCommsChannel,
    this.onCommsAction,
    this.onCommsCompose,
    this.commsDisconnected = false,
    this.onProfile,
    this.profiles = const {},
    required this.onRefresh,
    this.features = const {},
    this.onFeatureAction,
    this.localTools,
  });
  final MenuWorkspaceController controller;
  final MenuFriendsView? friends;
  final void Function(String action, String key, String value)? onFriendsAction;
  final MenuCommsView? comms;
  final String commsChannel;
  final ValueChanged<String>? onCommsChannel;
  final void Function(String, String)? onCommsAction;
  final void Function(String action, String key, String text, int revision)?
  onCommsCompose;
  final bool commsDisconnected;
  final void Function(String source, String key)? onProfile;
  final Map<String, MenuProfileView> profiles;
  final ValueChanged<String> onRefresh;
  final Map<String, MenuFeatureView> features;
  final void Function(String tool, String key, String value)? onFeatureAction;
  final MenuLocalToolsController? localTools;
  @override
  Widget build(BuildContext context) => MenuOverlayWorkspace(
    controller: controller,
    bridgeStyle: true,
    closeLabel: '关闭窗口',
    moveLabel: '拖动窗口',
    resizeLabel: '调整窗口大小',
    panels: [
      if (onFeatureAction != null)
        for (final entry in const {
          'organizations': '组织',
          'rooms': '房间',
          'hud': '信息浮层',
        }.entries)
          MenuPanelContent(
            id: entry.key,
            title: entry.value,
            icon: StarBridgeIconSemantic.friends,
            builder: (_, _) => entry.key == 'organizations'
                ? MenuOrganizationsPanel(
                    view:
                        features[entry.key] ?? const MenuFeatureView('loading'),
                    onProfile: onProfile == null
                        ? null
                        : (key) => onProfile!('organizations', key),
                    onAction: (key, value) =>
                        onFeatureAction!(entry.key, key, value),
                  )
                : MenuFeaturePanel(
                    view:
                        features[entry.key] ?? const MenuFeatureView('loading'),
                    onAction: (key, value) =>
                        onFeatureAction!(entry.key, key, value),
                  ),
          ),
      if (localTools != null) ...[
        MenuPanelContent(
          id: 'screenshot',
          title: '截图',
          icon: StarBridgeIconSemantic.friends,
          builder: (_, _) => MenuImageTool(tools: localTools!, capture: true),
        ),
        MenuPanelContent(
          id: 'image',
          title: '参考图',
          icon: StarBridgeIconSemantic.friends,
          builder: (_, _) => MenuImageTool(tools: localTools!),
        ),
        MenuPanelContent(
          id: 'browser',
          title: '浏览器',
          icon: StarBridgeIconSemantic.friends,
          builder: (_, _) =>
              MenuBrowserTool(call: localTools!.call, workspace: controller),
        ),
        MenuPanelContent(
          id: 'settings',
          title: '菜单设置',
          icon: StarBridgeIconSemantic.friends,
          builder: (_, _) =>
              MenuLocalSettings(tools: localTools!, workspace: controller),
        ),
      ],
      for (final entry in profiles.entries)
        MenuPanelContent(
          id: entry.key,
          title: '个人页面',
          icon: StarBridgeIconSemantic.friends,
          builder: (_, _) => MenuProfileWindowPage(
            view: entry.value,
            onRefresh: () => onRefresh(entry.key),
          ),
        ),
      MenuPanelContent(
        id: 'friends',
        title: '好友',
        icon: StarBridgeIconSemantic.friends,
        builder: (_, _) => friends == null
            ? SingleChildScrollView(
                key: const ValueKey('menu-scroll-friends'),
                child: BridgeFriendsPreview(
                  embedded: true,
                  onClose: () => controller.close('friends'),
                ),
              )
            : MenuFriendsPanel(
                onAction: onFriendsAction,
                onChat: onCommsAction == null
                    ? null
                    : (key) {
                        onCommsChannel?.call('private');
                        controller.open('comms');
                        onCommsAction!('friend', key);
                      },
                embedded: true,
                view: friends!,
                onClose: () => controller.close('friends'),
                onProfile: onProfile == null
                    ? null
                    : (key) => onProfile!('friends', key),
              ),
      ),
      MenuPanelContent(
        id: 'comms',
        title: '通讯',
        icon: StarBridgeIconSemantic.notifications,
        builder: (_, _) => friends == null
            ? SingleChildScrollView(
                child: BridgeCommsPreview(
                  embedded: true,
                  onClose: () => controller.close('comms'),
                ),
              )
            : comms != null && onCommsAction != null
            ? MenuCommsPanel(
                active: controller.activeId == 'comms' && controller.visible,
                embedded: true,
                view: comms!,
                organization: features['organizationChat'],
                onOrganizationProfile: onProfile == null
                    ? null
                    : (key) => onProfile!('organizationChat', key),
                organizationSelected: commsChannel == 'organizationChat',
                onConversationKind: onCommsChannel,
                onOrganizationAction: (key, value) =>
                    onFeatureAction?.call('organizationChat', key, value),
                onClose: () => controller.close('comms'),
                onAction: onCommsAction!,
                onCompose: onCommsCompose,
                disconnected: commsDisconnected,
                onProfile: onProfile == null
                    ? null
                    : (key) => onProfile!('comms', key),
              )
            : const BridgePlate(framed: false, child: BridgeCaption('通讯尚未接入。')),
      ),
    ],
  );
}
