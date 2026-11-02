import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/styles/attention_badge_palette.dart';
import '../../design_system/interaction/starbridge_action_button.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'menu_chrome_hint.dart';

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
                        MenuChromeIconAction(
                          controlKey: const ValueKey('menu-settings'),
                          label: settingsLabel,
                          onActivate: (_) => onSettings!(),
                          icon: const StarBridgeIcon(
                            StarBridgeIconSemantic.settings,
                          ),
                        ),
                      if (compact)
                        MenuChromeIconAction(
                          controlKey: const ValueKey('menu-return'),
                          label: returnLabel,
                          onActivate: (_) => onReturn(),
                          icon: const StarBridgeIcon(
                            StarBridgeIconSemantic.windowClose,
                          ),
                        )
                      else
                        _ReturnAction(label: returnLabel, onReturn: onReturn),
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

/// Keep the original TextButton.icon defaults, including scaled gap and themed
/// icon alignment, without changing the shared button module for one caller.
class _ReturnAction extends StatelessWidget {
  const _ReturnAction({required this.label, required this.onReturn});
  final String label;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    const icon = StarBridgeIcon(StarBridgeIconSemantic.windowClose);
    final original = TextButton.icon(
      onPressed: onReturn,
      icon: icon,
      label: Text(label),
    );
    final style = (TextButtonTheme.of(context).style ?? const ButtonStyle())
        .merge(original.defaultStyleOf(context));
    final theme = Theme.of(context);
    final adjustment =
        (style.visualDensity ?? theme.visualDensity).baseSizeAdjustment;
    final target =
        (style.tapTargetSize ?? theme.materialTapTargetSize) ==
            MaterialTapTargetSize.padded
        ? kMinInteractiveDimension
        : 0.0;
    final minimum = style.minimumSize!.resolve({})!;
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      2.0,
    );
    final children = <Widget>[
      IconTheme.merge(
        data: IconThemeData(size: style.iconSize?.resolve({})),
        child: icon,
      ),
      Flexible(
        child: Text(
          label,
          style: style.textStyle
              ?.resolve({})
              ?.copyWith(
                inherit: false,
                color: style.foregroundColor?.resolve({}),
              ),
        ),
      ),
    ];
    return StarBridgeActionButton(
      controlKey: const ValueKey('menu-return'),
      kind: StarBridgeActionKind.quiet,
      nativeStyle: style,
      minHeight: math.max(
        minimum.height + adjustment.dy,
        target + adjustment.dy,
      ),
      onActivate: (_) => onReturn(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8 - (scale - 1) * 4,
        children: style.iconAlignment == IconAlignment.end
            ? children.reversed.toList()
            : children,
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton(this.tool);
  final MenuOverlayTool tool;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MergeSemantics(
      child: Semantics(
        selected: tool.isActive,
        child: MenuChromeHint(
          message: tool.onActivate == null
              ? tool.unavailableReason!
              : tool.label,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.space.xs),
            child: StarBridgeActionButton(
              controlKey: ValueKey('menu-tool-${tool.id}'),
              kind: StarBridgeActionKind.quiet,
              onActivate: tool.onActivate == null
                  ? null
                  : (_) => tool.onActivate!(),
              nativeStyle: tool.isActive
                  ? TextButton.styleFrom(
                      backgroundColor: tokens.colors.accent.withValues(
                        alpha: 0.16,
                      ),
                    )
                  : const ButtonStyle(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Badge(
                    key: ValueKey('menu-unread-${tool.id}'),
                    backgroundColor: AttentionBadgePalette.background,
                    textColor: AttentionBadgePalette.foreground,
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
      ),
    );
  }
}
