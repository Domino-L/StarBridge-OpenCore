import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// A presentation-only registration. Business permissions and subscriptions
/// remain with the caller. All text is already localized by composition.
@immutable
final class MenuOverlayTool {
  const MenuOverlayTool({
    required this.id,
    required this.label,
    required this.icon,
    this.onActivate,
    this.unavailableReason,
    this.isOpen = false,
    this.isActive = false,
    this.hasUnread = false,
  }) : assert(id != ''),
       assert(onActivate != null || unavailableReason != null),
       assert(!isActive || isOpen);

  final String id;
  final String label;
  final StarBridgeIconSemantic icon;
  final VoidCallback? onActivate;
  final String? unavailableReason;
  final bool isOpen;
  final bool isActive;
  final bool hasUnread;
}

/// Outer menu frame only: no platform window, timers, persistence or backend.
/// The workspace owns panels; composition owns tool order and visibility.
class MenuOverlayFrame extends StatelessWidget {
  MenuOverlayFrame({
    super.key,
    required this.contextLabel,
    required this.returnLabel,
    required this.settingsLabel,
    required this.onReturn,
    required Iterable<MenuOverlayTool> tools,
    this.onSettings,
    this.clockLabel,
    this.workspace = const SizedBox.expand(),
  }) : tools = List.unmodifiable(tools) {
    final ids = <String>{};
    for (final tool in this.tools) {
      if (tool.id.trim().isEmpty || !ids.add(tool.id)) {
        throw ArgumentError('Menu tool IDs must be nonempty and unique.');
      }
    }
  }

  final String contextLabel;
  final String returnLabel;
  final String settingsLabel;
  final String? clockLabel;
  final VoidCallback onReturn;
  final VoidCallback? onSettings;
  final List<MenuOverlayTool> tools;
  final Widget workspace;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // The native host owns backdrop/dimming. This frame does not obscure the
    // workspace with a full-screen Material or assume a game window exists.
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(tokens.space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuSurface(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 600;
                  final controls = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (clockLabel != null)
                        Flexible(
                          child: Text(
                            clockLabel!,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (onSettings != null)
                        IconButton(
                          tooltip: settingsLabel,
                          onPressed: onSettings,
                          icon: const StarBridgeIcon(
                            StarBridgeIconSemantic.settings,
                          ),
                        ),
                      if (compact)
                        IconButton(
                          key: const ValueKey('menu-return'),
                          tooltip: returnLabel,
                          onPressed: onReturn,
                          icon: const StarBridgeIcon(
                            StarBridgeIconSemantic.windowClose,
                          ),
                        )
                      else
                        TextButton.icon(
                          key: const ValueKey('menu-return'),
                          onPressed: onReturn,
                          icon: const StarBridgeIcon(
                            StarBridgeIconSemantic.windowClose,
                          ),
                          label: Text(returnLabel),
                        ),
                    ],
                  );
                  final title = Text(
                    contextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title,
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: controls,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      controls,
                    ],
                  );
                },
              ),
            ),
            Expanded(child: workspace),
            if (tools.isNotEmpty)
              Align(
                alignment: Alignment.bottomCenter,
                child: _MenuSurface(
                  child: SingleChildScrollView(
                    key: const ValueKey('menu-dock'),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final tool in tools) _ToolButton(tool)],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuSurface extends StatelessWidget {
  const _MenuSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surfaces.panel.fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.shape.radiusMedium),
        side: BorderSide(color: tokens.surfaces.panel.border),
      ),
      child: Padding(padding: EdgeInsets.all(tokens.space.sm), child: child),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton(this.tool);
  final MenuOverlayTool tool;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      selected: tool.isActive,
      child: Tooltip(
        message: tool.onActivate == null ? tool.unavailableReason! : tool.label,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.space.xs),
          child: TextButton(
            key: ValueKey('menu-tool-${tool.id}'),
            onPressed: tool.onActivate,
            style: tool.isActive
                ? TextButton.styleFrom(
                    backgroundColor: tokens.colors.accent.withValues(
                      alpha: 0.16,
                    ),
                  )
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  key: ValueKey('menu-unread-${tool.id}'),
                  isLabelVisible: tool.hasUnread,
                  child: StarBridgeIcon(tool.icon),
                ),
                Text(tool.label),
                SizedBox(
                  height: 4,
                  width: 16,
                  child: tool.isOpen
                      ? DecoratedBox(
                          key: ValueKey('menu-open-${tool.id}'),
                          decoration: BoxDecoration(
                            color: tool.isActive
                                ? tokens.colors.accent
                                : tokens.colors.textSecondary,
                            borderRadius: BorderRadius.circular(
                              tokens.shape.radiusSmall,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
