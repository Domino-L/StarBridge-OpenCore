import 'package:flutter/material.dart';

import '../../design_system/brand/brand_lockup.dart';
import '../../design_system/brand/brand_lockup_spec.dart';
import 'menu_bridge_style.dart';
import '../../platform/window/menu_toolbar_preferences.dart';
import '../localization/app_strings.dart';
import '../shell/widgets/attention_badge.dart';
import '../../platform/window/menu_attention.dart';

enum BridgePreviewPanel {
  friends,
  comms,
  organizations,
  rooms,
  hud,
  screenshot,
  image,
  browser,
}

/// One brand-bearing rail. Open and foreground are independent window states.
class BridgePreviewDock extends StatelessWidget {
  const BridgePreviewDock({
    super.key,
    required this.selected,
    required this.onToggle,
    this.openPanels = const {},
    this.featuresEnabled = false,
    this.localToolsEnabled = false,
    this.onRecover,
    this.preferences = const MenuToolbarPreferences(),
    this.attention = const MenuAttention(),
    this.hudBusy = false,
  });
  final BridgePreviewPanel? selected;
  final ValueChanged<BridgePreviewPanel> onToggle;
  final ValueChanged<BridgePreviewPanel>? onRecover;
  final Set<BridgePreviewPanel> openPanels;
  final bool featuresEnabled;
  final bool localToolsEnabled;
  final MenuToolbarPreferences preferences;
  final MenuAttention attention;
  final bool hudBusy;
  int count(BridgePreviewPanel panel) =>
      preferences.showUnreadBadges ? attention.count(panel.name) : 0;
  String label(BuildContext context, BridgePreviewPanel panel) {
    final strings = AppStrings.of(context);
    final title = strings.text('menu.tools.${panel.name}');
    return count(panel) == 0
        ? title
        : '$title · ${strings.text('menu.toolbar.attention').replaceAll('{count}', '${count(panel)}')}';
  }

  static const tools = [
    (MenuGlyph.overlay, '信息浮层', BridgePreviewPanel.hud),
    (MenuGlyph.group, '组织', BridgePreviewPanel.organizations),
    (MenuGlyph.friends, '好友', BridgePreviewPanel.friends),
    (MenuGlyph.chat, '通讯', BridgePreviewPanel.comms),
    (MenuGlyph.room, '房间', BridgePreviewPanel.rooms),
    (MenuGlyph.camera, '全屏截屏', BridgePreviewPanel.screenshot),
    (MenuGlyph.image, '参考图', BridgePreviewPanel.image),
    (MenuGlyph.browser, '浏览器', BridgePreviewPanel.browser),
  ];

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: MenuBridgeColors.of(context).line,
                  endIndent: 18,
                ),
              ),
              const BrandLockup(scale: BrandLockupScale.navigationExpanded),
              Expanded(
                child: Divider(
                  color: MenuBridgeColors.of(context).line,
                  indent: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: BridgeInk.panel,
              border: Border(
                bottom: BorderSide(color: MenuBridgeColors.of(context).line),
              ),
            ),
            child: SingleChildScrollView(
              key: const ValueKey('menu-visual-dock'),
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (icon, _, panel) in orderedTools) ...[
                    if (panel == BridgePreviewPanel.screenshot)
                      const SizedBox(
                        height: 32,
                        child: VerticalDivider(
                          color: BridgeInk.line,
                          width: 24,
                        ),
                      ),
                    SizedBox(
                      width: switch (preferences.density) {
                        'compact' => 66,
                        'comfortable' => 94,
                        _ => 82,
                      },
                      child: GestureDetector(
                        onSecondaryTapDown:
                            panel != BridgePreviewPanel.hud &&
                                openPanels.contains(panel) &&
                                onRecover != null
                            ? (details) async {
                                final action = await showMenu<String>(
                                  context: context,
                                  position: RelativeRect.fromLTRB(
                                    details.globalPosition.dx,
                                    details.globalPosition.dy,
                                    0,
                                    0,
                                  ),
                                  items: const [
                                    PopupMenuItem(
                                      value: 'recover',
                                      child: Text('移回当前屏幕'),
                                    ),
                                  ],
                                );
                                if (action == 'recover' && context.mounted) {
                                  onRecover!(panel);
                                }
                              }
                            : null,
                        child: Tooltip(
                          message: label(context, panel),
                          child: BridgeMenuAction(
                            key: ValueKey('menu-tool-${icon.name}'),
                            label: label(context, panel),
                            selected: selected == panel,
                            onPressed:
                                (panel == BridgePreviewPanel.hud && hudBusy) ||
                                    (!featuresEnabled &&
                                        const {
                                          BridgePreviewPanel.organizations,
                                          BridgePreviewPanel.rooms,
                                          BridgePreviewPanel.hud,
                                        }.contains(panel)) ||
                                    (!localToolsEnabled &&
                                        const {
                                          BridgePreviewPanel.screenshot,
                                          BridgePreviewPanel.image,
                                          BridgePreviewPanel.browser,
                                        }.contains(panel))
                                ? null
                                : () => onToggle(panel),
                            padding: EdgeInsets.symmetric(
                              vertical: preferences.density == 'compact'
                                  ? 10
                                  : 16,
                              horizontal: 4,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AttentionIconBadge(
                                  key: ValueKey('menu-attention-${panel.name}'),
                                  count: count(panel),
                                  child: MenuGlyphView(
                                    icon,
                                    size: 27,
                                    color: selected == panel
                                        ? BridgeInk.blue
                                        : BridgeInk.text,
                                  ),
                                ),
                                if (preferences.labels != 'iconsOnly') ...[
                                  const SizedBox(height: 9),
                                  Text(
                                    AppStrings.of(context)
                                        .text('menu.tools.${panel.name}'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 5),
                                Container(
                                  key: ValueKey('menu-open-${icon.name}'),
                                  width: 16,
                                  height: 2,
                                  color: openPanels.contains(panel)
                                      ? BridgeInk.blue
                                      : Colors.transparent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Iterable<(MenuGlyph, String, BridgePreviewPanel)> get orderedTools sync* {
    for (final id in preferences.order) {
      if (!preferences.hidden.contains(id)) {
        yield tools.firstWhere((tool) => tool.$3.name == id);
      }
    }
  }
}
