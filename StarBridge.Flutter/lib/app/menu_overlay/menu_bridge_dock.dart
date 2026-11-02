import 'package:flutter/material.dart';

import '../../design_system/brand/brand_lockup.dart';
import '../../design_system/brand/brand_lockup_spec.dart';
import 'menu_bridge_style.dart';
import 'menu_chrome_hint.dart';
import 'menu_native_popup.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
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
  execHangar,
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
    this.execHangarEnabled = false,
    this.recoveryIdentities = const {},
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
  final bool execHangarEnabled;

  /// Opaque current panel leases, supplied by the workspace; never persisted.
  final Map<BridgePreviewPanel, Object> recoveryIdentities;
  int count(BridgePreviewPanel panel) =>
      preferences.showUnreadBadges ? attention.count(panel.name) : 0;
  String label(BuildContext context, BridgePreviewPanel panel) {
    final strings = AppStrings.of(context);
    final title = strings.text('menu.tools.${panel.name}');
    return count(panel) == 0
        ? title
        : '$title · ${strings.text('menu.toolbar.attention').replaceAll('{count}', '${count(panel)}')}';
  }

  bool _canOpen(BridgePreviewPanel panel) =>
      !(panel == BridgePreviewPanel.execHangar && !execHangarEnabled) &&
      !(!featuresEnabled &&
          const {
            BridgePreviewPanel.organizations,
            BridgePreviewPanel.rooms,
            BridgePreviewPanel.hud,
          }.contains(panel)) &&
      !(!localToolsEnabled &&
          const {
            BridgePreviewPanel.screenshot,
            BridgePreviewPanel.image,
            BridgePreviewPanel.browser,
          }.contains(panel));

  static const tools = [
    (MenuGlyph.overlay, 'menu.tools.hud', BridgePreviewPanel.hud),
    (
      MenuGlyph.group,
      'menu.tools.organizations',
      BridgePreviewPanel.organizations,
    ),
    (MenuGlyph.friends, 'menu.tools.friends', BridgePreviewPanel.friends),
    (MenuGlyph.chat, 'menu.tools.comms', BridgePreviewPanel.comms),
    (MenuGlyph.room, 'menu.tools.rooms', BridgePreviewPanel.rooms),
    (MenuGlyph.camera, '全屏截屏', BridgePreviewPanel.screenshot),
    (MenuGlyph.image, 'menu.tools.image', BridgePreviewPanel.image),
    (MenuGlyph.browser, 'menu.tools.browser', BridgePreviewPanel.browser),
    (MenuGlyph.ship, '行政机库', BridgePreviewPanel.execHangar),
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
                      child: MenuNativePopup(
                        identity: recoveryIdentities[panel] ?? panel,
                        contextMenu: true,
                        enabled:
                            panel != BridgePreviewPanel.hud &&
                            openPanels.contains(panel) &&
                            onRecover != null,
                        label: AppStrings.of(context).text('menu.overlay.window.recover'),
                        entries: [
                          StarBridgeMenuEntry(
                            id: 'recover',
                            label: AppStrings.of(context).text('menu.overlay.window.recover'),
                            child: Text(AppStrings.of(context).text('menu.overlay.window.recover')),
                            onActivate: (_) {
                              if (context.mounted &&
                                  panel != BridgePreviewPanel.hud &&
                                  openPanels.contains(panel) &&
                                  onRecover != null) {
                                onRecover!(panel);
                              }
                            },
                          ),
                        ],
                        builder: (context, controller, focus, toggle) =>
                            _DockContextFocus(
                              key: ValueKey('menu-context-focus-${panel.name}'),
                              node: focus,
                              primaryEnabled: _canOpen(panel),
                              contextEnabled:
                                  panel != BridgePreviewPanel.hud &&
                                  openPanels.contains(panel) &&
                                  onRecover != null,
                              child: Builder(
                                builder: (context) => DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color:
                                            !_canOpen(panel) &&
                                                Focus.of(context).hasFocus
                                            ? MenuBridgeColors.of(context).blue
                                            : Colors.transparent,
                                      ),
                                      bottom: BorderSide(
                                        color:
                                            !_canOpen(panel) &&
                                                Focus.of(context).hasFocus
                                            ? MenuBridgeColors.of(context).blue
                                            : Colors.transparent,
                                      ),
                                    ),
                                  ),
                                  child: GestureDetector(
                                    excludeFromSemantics: true,
                                    onSecondaryTapDown: (_) =>
                                        toggle(InteractionSource.pointer),
                                    child: MenuChromeHint(
                                      visible: !controller.isOpen,
                                      message: label(context, panel),
                                      child: BridgeMenuAction(
                                        focusNode: _canOpen(panel)
                                            ? focus
                                            : null,
                                        key: ValueKey('menu-tool-${icon.name}'),
                                        label: label(context, panel),
                                        selected: selected == panel,
                                        onPressed: _canOpen(panel)
                                            ? () => onToggle(panel)
                                            : null,
                                        padding: EdgeInsets.symmetric(
                                          vertical:
                                              preferences.density == 'compact'
                                              ? 10
                                              : 16,
                                          horizontal: 4,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            AttentionIconBadge(
                                              key: ValueKey(
                                                'menu-attention-${panel.name}',
                                              ),
                                              count: count(panel),
                                              child: MenuGlyphView(
                                                icon,
                                                size: 27,
                                                color: selected == panel
                                                    ? BridgeInk.blue
                                                    : BridgeInk.text,
                                              ),
                                            ),
                                            if (preferences.labels !=
                                                'iconsOnly') ...[
                                              const SizedBox(height: 9),
                                              Text(
                                                AppStrings.of(context).text(
                                                  'menu.tools.${panel.name}',
                                                ),
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
                                              key: ValueKey(
                                                'menu-open-${icon.name}',
                                              ),
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

/// Keep an independently available context action keyboard-reachable when its
/// primary command changes availability. The anchor node migrates between the
/// original button and this fallback; restore only focus that it already held.
class _DockContextFocus extends StatefulWidget {
  const _DockContextFocus({
    required this.node,
    required this.primaryEnabled,
    required this.contextEnabled,
    required this.child,
    super.key,
  });
  final FocusNode node;
  final bool primaryEnabled, contextEnabled;
  final Widget child;
  @override
  State<_DockContextFocus> createState() => _DockContextFocusState();
}

class _DockContextFocusState extends State<_DockContextFocus> {
  int _generation = 0;
  @override
  void didUpdateWidget(_DockContextFocus old) {
    super.didUpdateWidget(old);
    final generation = ++_generation;
    if (old.node == widget.node &&
        old.primaryEnabled != widget.primaryEnabled &&
        widget.node.hasFocus &&
        (widget.primaryEnabled || widget.contextEnabled)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            generation == _generation &&
            widget.node.context != null &&
            (widget.primaryEnabled || widget.contextEnabled)) {
          widget.node.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.primaryEnabled ? null : widget.node,
    canRequestFocus: !widget.primaryEnabled && widget.contextEnabled,
    skipTraversal: widget.primaryEnabled,
    child: widget.child,
  );
}
