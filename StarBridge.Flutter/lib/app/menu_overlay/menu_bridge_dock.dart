import 'package:flutter/material.dart';

import '../../design_system/brand/brand_lockup.dart';
import '../../design_system/brand/brand_lockup_spec.dart';
import 'menu_bridge_style.dart';

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
  });
  final BridgePreviewPanel? selected;
  final ValueChanged<BridgePreviewPanel> onToggle;
  final ValueChanged<BridgePreviewPanel>? onRecover;
  final Set<BridgePreviewPanel> openPanels;
  final bool featuresEnabled;
  final bool localToolsEnabled;
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
          const Row(
            children: [
              Expanded(child: Divider(color: BridgeInk.line, endIndent: 18)),
              BrandLockup(scale: BrandLockupScale.navigationExpanded),
              Expanded(child: Divider(color: BridgeInk.line, indent: 18)),
            ],
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: BridgeInk.panel,
              border: Border(bottom: BorderSide(color: BridgeInk.line)),
            ),
            child: SingleChildScrollView(
              key: const ValueKey('menu-visual-dock'),
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (icon, label, panel) in tools) ...[
                    if (label == '全屏截屏')
                      const SizedBox(
                        height: 32,
                        child: VerticalDivider(
                          color: BridgeInk.line,
                          width: 24,
                        ),
                      ),
                    SizedBox(
                      width: 104,
                      child: GestureDetector(
                        onSecondaryTapDown:
                            openPanels.contains(panel) && onRecover != null
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
                        child: BridgeMenuAction(
                          key: ValueKey('menu-tool-${icon.name}'),
                          label: label,
                          selected: selected == panel,
                          onPressed:
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
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 4,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MenuGlyphView(
                                icon,
                                size: 27,
                                color: selected == panel
                                    ? BridgeInk.blue
                                    : BridgeInk.text,
                              ),
                              const SizedBox(height: 9),
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  letterSpacing: .5,
                                ),
                              ),
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
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
