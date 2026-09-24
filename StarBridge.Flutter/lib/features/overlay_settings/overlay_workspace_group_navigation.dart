import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_schema.dart';

class OverlayWorkspaceGroupNavigation extends StatelessWidget {
  const OverlayWorkspaceGroupNavigation({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: const Key('overlay-group-navigation'),
      role: SurfaceRole.panel,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(tokens.space.md),
              child: Text(
                _copy(context, 'overlay.workspace.sections'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.colors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Divider(color: tokens.surfaces.panel.border, height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(vertical: tokens.space.xs),
                children: overlayWorkspaceNavigationGroupOrder
                    .map(
                      (group) => _GroupNavigationItem(
                        group: group,
                        selected: selected == group,
                        onTap: () => onSelected(group),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupNavigationItem extends StatelessWidget {
  const _GroupNavigationItem({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final String group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = selected
        ? tokens.colors.accent
        : tokens.colors.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: Key('overlay-group-nav-$group'),
        onTap: onTap,
        hoverColor: tokens.colors.accent.withValues(alpha: 0.08),
        focusColor: tokens.colors.accent.withValues(alpha: 0.10),
        highlightColor: tokens.colors.accent.withValues(alpha: 0.12),
        splashColor: tokens.colors.accent.withValues(alpha: 0.22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? tokens.colors.accentSoft : Colors.transparent,
              border: BorderDirectional(
                start: BorderSide(
                  color: selected ? tokens.colors.accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: EdgeInsetsDirectional.only(
              start: tokens.space.sm,
              end: tokens.space.sm,
            ),
            child: Row(
              children: [
                StarBridgeIcon(_groupIcon(group), size: 18, color: accent),
                SizedBox(width: tokens.space.sm),
                Expanded(
                  child: Text(
                    overlayWorkspaceGroupName(context, group),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected ? tokens.colors.textPrimary : accent,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static StarBridgeIconSemantic _groupIcon(String group) => switch (group) {
    'notice' => StarBridgeIconSemantic.notifications,
    'fleetOverview' => StarBridgeIconSemantic.officialFleet,
    'members' => StarBridgeIconSemantic.friends,
    'appearance' => StarBridgeIconSemantic.scene,
    'crosshair' => StarBridgeIconSemantic.statusIdentity,
    'startup' => StarBridgeIconSemantic.playtime,
    'events' => StarBridgeIconSemantic.reminder,
    'chat' => StarBridgeIconSemantic.community,
    _ => StarBridgeIconSemantic.dragHandle,
  };
}

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
