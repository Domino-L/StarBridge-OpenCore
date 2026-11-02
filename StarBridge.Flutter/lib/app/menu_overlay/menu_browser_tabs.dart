import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import 'menu_bridge_style.dart';
import 'menu_browser_hint.dart';
import 'menu_browser_state.dart';
import 'menu_workspace_controller.dart';

/// Tab chrome; native commands, drafts and key ownership stay with the tool.
class MenuBrowserTabs extends StatelessWidget {
  const MenuBrowserTabs({
    super.key,
    required this.state,
    required this.ready,
    required this.busy,
    required this.routeActive,
    required this.workspace,
    required this.keyForTab,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
  });

  final MenuBrowserState? state;
  final bool ready, busy, routeActive;
  final MenuWorkspaceController workspace;
  final GlobalKey Function(String) keyForTab;
  final ValueChanged<String> onSelect, onClose;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final current = state;
    final ink = MenuBridgeColors.of(context);
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tab in current?.tabs ?? <MenuBrowserTab>[])
                  Container(
                    key: keyForTab(tab.id),
                    constraints: const BoxConstraints(maxWidth: 216),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: tab.id == current?.activeId
                          ? ink.selected
                          : ink.panel,
                      border: Border(
                        bottom: BorderSide(
                          color: tab.id == current?.activeId
                              ? ink.blue
                              : ink.line,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: MenuBrowserHint(
                            workspace: workspace,
                            active: routeActive,
                            builder: (visibility) => StarBridgeTooltip(
                              onVisibilityChanged: visibility,
                              message: tab.url == 'about:blank'
                                  ? menuText(
                                      context,
                                      'menu.overlay.browser.newTab',
                                    )
                                  : tab.url,
                              child: BridgeMenuAction(
                                key: ValueKey('browser-tab-${tab.id}'),
                                label: tab.title.isEmpty
                                    ? menuText(
                                        context,
                                        'menu.overlay.browser.newTab',
                                      )
                                    : tab.title,
                                selected: tab.id == current?.activeId,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                onPressed: busy ? null : () => onSelect(tab.id),
                                child: Text(
                                  tab.title.isEmpty
                                      ? menuText(
                                          context,
                                          'menu.overlay.browser.newTab',
                                        )
                                      : tab.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                        MenuBrowserHint(
                          workspace: workspace,
                          active: routeActive,
                          builder: (visibility) => StarBridgeNativeIconAction(
                            onHintVisibilityChanged: visibility,
                            controlKey: ValueKey('browser-close-${tab.id}'),
                            label: menuText(
                              context,
                              'menu.overlay.browser.closeTab',
                            ),
                            onActivate: busy ? null : (_) => onClose(tab.id),
                            icon: const StandardIcon(
                              StandardIconSemantic.close,
                              size: 16,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            padding: const EdgeInsets.all(8),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        MenuBrowserHint(
          workspace: workspace,
          active: routeActive,
          builder: (visibility) => StarBridgeNativeIconAction(
            onHintVisibilityChanged: visibility,
            controlKey: const ValueKey('browser-new-tab'),
            label: current != null && current.tabs.length >= current.limit
                ? menuText(context, 'menu.overlay.browser.maxTabs', {
                    'limit': current.limit,
                  })
                : menuText(context, 'menu.overlay.browser.addTab'),
            onActivate:
                ready &&
                    !busy &&
                    current != null &&
                    current.tabs.length < current.limit
                ? (_) => onNew()
                : null,
            icon: const StandardIcon(StandardIconSemantic.add),
          ),
        ),
      ],
    );
  }
}
