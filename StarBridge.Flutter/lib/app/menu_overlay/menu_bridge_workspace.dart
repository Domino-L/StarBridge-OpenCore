import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../platform/window/menu_shortcut_settings.dart';
import '../../platform/window/menu_screenshot_directory.dart';
import '../../features/overlay_settings/menu_browser_resume_controller.dart';
import '../composition/menu_profile_page.dart';
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
import 'menu_rooms_panel.dart';
import 'menu_local_tools.dart';

class MenuBridgeWorkspace extends StatelessWidget {
  const MenuBridgeWorkspace({
    super.key,
    required this.controller,
    this.friends,
    this.onFriendsAction,
    this.comms,
    this.onCommsAction,
    this.onCommsCompose,
    this.commsDisconnected = false,
    this.onProfile,
    this.profiles = const {},
    required this.onRefresh,
    this.features = const {},
    this.onFeatureAction,
    this.localTools,
    this.shortcutSettings,
    this.browserResume,
    this.screenshotDirectory,
    this.safeMode = false,
  });
  final MenuWorkspaceController controller;
  final MenuFriendsView? friends;
  final void Function(String action, String key, String value)? onFriendsAction;
  final MenuCommsView? comms;
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
  final MenuShortcutSettingsPort? shortcutSettings;
  final MenuBrowserResumeController? browserResume;
  final MenuScreenshotDirectoryPort? screenshotDirectory;
  final bool safeMode;
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
                    active:
                        controller.activeId == 'organizations' &&
                        controller.panelsVisible,
                    view:
                        features[entry.key] ?? const MenuFeatureView('loading'),
                    onProfile: onProfile == null
                        ? null
                        : (key) => onProfile!('organizations', key),
                    onAction: (key, value) =>
                        onFeatureAction!(entry.key, key, value),
                  )
                : entry.key == 'rooms'
                ? MenuRoomsPanel(
                    showRoomCode: localTools?.display.roomCodeVisible ?? true,
                    view:
                        features[entry.key] ?? const MenuFeatureView('loading'),
                    active:
                        controller.activeId == 'rooms' && controller.panelsVisible,
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
          chromeHidden: localTools!.referenceChromeHidden,
          builder: (_, _) =>
              MenuImageTool(tools: localTools!, workspace: controller),
        ),
        MenuPanelContent(
          id: 'browser',
          title: '浏览器',
          icon: StarBridgeIconSemantic.friends,
          builder: (_, _) => MenuBrowserTool(
            safeMode: safeMode,
            call: localTools!.call,
            workspace: controller,
            preferences: localTools!.browser,
            resume: browserResume,
          ),
        ),
        MenuPanelContent(
          id: 'settings',
          title: '菜单设置',
          icon: StarBridgeIconSemantic.friends,
          builder: (_, _) => MenuLocalSettings(
            tools: localTools!,
            workspace: controller,
            shortcutSettings: shortcutSettings,
            browserResume: browserResume,
            screenshotDirectory: screenshotDirectory,
          ),
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
                sort: localTools?.social.friendSort ?? 'onlineFirst',
                onAction: onFriendsAction,
                onChat: onCommsAction == null
                    ? null
                    : (key) {
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
                active: controller.activeId == 'comms' && controller.panelsVisible,
                embedded: true,
                view: comms!,
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
