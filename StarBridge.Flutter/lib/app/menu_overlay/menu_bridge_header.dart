import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';

import '../../platform/window/menu_display_preferences.dart';
import 'menu_bridge_style.dart';
import 'menu_clock.dart';
import '../localization/app_strings.dart';

class MenuBridgeHeader extends StatelessWidget {
  const MenuBridgeHeader({
    super.key,
    required this.onDismiss,
    this.onSettings,
    this.onHud,
    this.hudEnabled,
    this.hudBusy = false,
    this.onToggleWindows,
    this.windowsHidden = false,
    this.display = const MenuDisplayPreferences(),
    this.presenceKey = 'presence.unknown',
    this.system24Hour,
    this.onEditWidgets,
    this.editingWidgets = false,
    this.onAddHangar,
    this.desktopWidget,
  });
  final VoidCallback onDismiss;
  final VoidCallback? onSettings, onHud, onToggleWindows;
  final bool windowsHidden;
  final bool? hudEnabled;
  final bool hudBusy;
  final MenuDisplayPreferences display;
  final String presenceKey;
  final bool? system24Hour;
  final VoidCallback? onEditWidgets;
  final bool editingWidgets;
  final VoidCallback? onAddHangar;
  final Widget? desktopWidget;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final locale = Localizations.localeOf(context);
      final traditional =
          locale.scriptCode == 'Hant' ||
          ['TW', 'HK', 'MO'].contains(locale.countryCode);
      final hudLabel = locale.languageCode == 'zh'
          ? (traditional
                ? (hudEnabled == null
                      ? '切換資訊浮層'
                      : hudEnabled!
                      ? '關閉資訊浮層'
                      : '開啟資訊浮層')
                : (hudEnabled == null
                      ? '切换信息浮层'
                      : hudEnabled!
                      ? '关闭信息浮层'
                      : '打开信息浮层'))
          : (hudEnabled == null
                ? 'Toggle information overlay'
                : hudEnabled!
                ? 'Close information overlay'
                : 'Open information overlay');
      final windowsLabel = locale.languageCode == 'zh'
          ? (locale.scriptCode == 'Hant' ||
                    ['TW', 'HK', 'MO'].contains(locale.countryCode)
                ? (windowsHidden ? '顯示所有視窗' : '隱藏所有視窗')
                : (windowsHidden ? '显示所有窗口' : '隐藏所有窗口'))
          : (windowsHidden ? 'Show all windows' : 'Hide all windows');
      final actions = Wrap(
        spacing: 18,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (editingWidgets && onAddHangar != null)
            BridgeMenuAction(
              key: const Key('menu-add-hangar-widget'),
              label: AppStrings.of(context).text('execHangar.widgetAdd'),
              onPressed: onAddHangar,
              child: Text(
                AppStrings.of(context).text('execHangar.widgetAddNamed'),
              ),
            ),
          if (onEditWidgets != null)
            BridgeMenuAction(
              key: const Key('menu-edit-widgets'),
              label: AppStrings.of(context).text(
                'execHangar.${editingWidgets ? 'widgetDone' : 'widgetEdit'}',
              ),
              onPressed: onEditWidgets,
              child: Text(
                AppStrings.of(context).text(
                  'execHangar.${editingWidgets ? 'widgetDone' : 'widgetEdit'}',
                ),
              ),
            ),
          BridgeMenuAction(
            key: const ValueKey('menu-toggle-all-windows'),
            label: windowsLabel,
            onPressed: onToggleWindows,
            child: Text(windowsLabel),
          ),
          BridgeMenuAction(
            label: menuText(context, 'navigation.settings'),
            onPressed: onSettings,
            child: BridgeLabel(
              MenuGlyph.settings,
              menuText(context, 'navigation.settings'),
            ),
          ),
          BridgeMenuAction(
            label: hudLabel,
            key: const ValueKey('menu-toggle-hud'),
            onPressed: hudBusy ? null : onHud,
            child: BridgeLabel(MenuGlyph.overlay, hudLabel),
          ),
          BridgeMenuAction(
            key: const ValueKey('menu-return'),
            label: menuText(context, 'overlay.menu.return'),
            onPressed: onDismiss,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(menuText(context, 'overlay.menu.return')),
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
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (display.showClock ||
                display.showDate ||
                display.showPresence ||
                desktopWidget != null)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: MenuClock(
                    preferences: display,
                    presenceKey: presenceKey,
                    system24Hour: system24Hour,
                    desktopWidget: desktopWidget,
                  ),
                ),
              ),
            const SizedBox(width: 24),
            Expanded(child: actions),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (display.showClock ||
              display.showDate ||
              display.showPresence ||
              desktopWidget != null)
            MenuClock(
              preferences: display,
              presenceKey: presenceKey,
              system24Hour: system24Hour,
              desktopWidget: desktopWidget,
            )
          else
            const SizedBox.shrink(),
          Flexible(child: actions),
        ],
      );
    },
  );
}
