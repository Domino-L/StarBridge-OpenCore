import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_preset_sources.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_projection.dart';
import 'overlay_workspace_schema.dart';

typedef OverlayGroupMark = ({bool off, bool ownSource});

/// A closed module and a module with its own source stay visible in the
/// group list itself, so neither is a hidden state.
OverlayGroupMark overlayWorkspaceGroupMark(
  OverlayWorkspaceProjection projection,
  String group,
) {
  final (show, module) = switch (group) {
    'notice' => ('showNotice', OverlaySourceModule.notice),
    'fleetOverview' => ('showSquads', OverlaySourceModule.overview),
    'members' => ('showMembers', OverlaySourceModule.members),
    'chat' => ('showChat', OverlaySourceModule.chat),
    'events' => ('showEventNotifications', OverlaySourceModule.events),
    _ => (null, null),
  };
  final sources = projection.sources;
  return (
    off: show != null && projection.settings?[show] == false,
    ownSource:
        module != null &&
        sources != null &&
        (sources.forModule(module).mode != OverlaySourceMode.none ||
            module == OverlaySourceModule.chat &&
                sources.chatSources.isNotEmpty),
  );
}

class OverlayWorkspaceGroupNavigation extends StatefulWidget {
  const OverlayWorkspaceGroupNavigation({
    required this.selected,
    required this.onSelected,
    this.groups = overlayWorkspaceNavigationGroupOrder,
    this.label,
    this.icon,
    this.title,
    this.keyPrefix = 'overlay-group',
    this.mark,
    super.key,
  });

  final OverlayGroupMark Function(String group)? mark;
  final String selected;
  final ValueChanged<String> onSelected;
  final List<String> groups;
  final String Function(String)? label;
  final StarBridgeIconSemantic Function(String)? icon;
  final String? title;
  final String keyPrefix;

  @override
  State<OverlayWorkspaceGroupNavigation> createState() =>
      _OverlayWorkspaceGroupNavigationState();
}

class _OverlayWorkspaceGroupNavigationState
    extends State<OverlayWorkspaceGroupNavigation> {
  String? _pendingTarget;
  InteractionSource _pendingSource = InteractionSource.programmatic;
  InteractionSource _changeSource = InteractionSource.programmatic;

  @override
  void didUpdateWidget(OverlayWorkspaceGroupNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _changeSource = _pendingTarget == widget.selected
          ? _pendingSource
          : InteractionSource.programmatic;
      _pendingTarget = null;
    }
  }

  void _activate(String group, InteractionSource source, SideNavLayout layout) {
    if (source == InteractionSource.keyboard) layout.finishMotion();
    _pendingTarget = group;
    _pendingSource = source;
    // No optimistic selection or delayed callback. Both existing workspace
    // owners synchronously project category selection; they keep all drafts.
    widget.onSelected(group);
  }

  void _step(String current, int delta, SideNavLayout layout) {
    if (widget.groups.isEmpty) return;
    final i = widget.groups.indexOf(current);
    final target = (i + delta).clamp(0, widget.groups.length - 1);
    if (i < 0 || i == target) return;
    final group = widget.groups[target];
    layout.focus(group);
    _activate(group, InteractionSource.keyboard, layout);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: Key('${widget.keyPrefix}-navigation'),
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
                widget.title ?? _copy(context, 'overlay.workspace.sections'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.colors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Divider(color: tokens.surfaces.panel.border, height: 1),
            Expanded(
              child: StarBridgeInteractionRegion(
                child: Builder(
                  builder: (context) => SuiteSideNav.tracked(
                    homeId: '__workspace_no_home__',
                    primaryIds: widget.groups,
                    personalIds: const [],
                    selectedId: widget.selected,
                    changeSource: _changeSource,
                    layoutBuilder: (context, layout) => ListView(
                      key: layout.viewportKey,
                      controller: layout.scrollController,
                      padding: EdgeInsets.symmetric(vertical: tokens.space.xs),
                      children: [
                        for (final group in widget.groups)
                          layout.anchor(
                            group,
                            _GroupNavigationItem(
                              group: group,
                              label: widget.label?.call(group),
                              icon: widget.icon?.call(group),
                              keyPrefix: widget.keyPrefix,
                              mark: widget.mark?.call(group),
                              selected: widget.selected == group,
                              focusNode: layout.focusNode(group),
                              onActivate: (source) =>
                                  _activate(group, source, layout),
                              onPrevious: () => _step(group, -1, layout),
                              onNext: () => _step(group, 1, layout),
                            ),
                          ),
                      ],
                    ),
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

class _GroupNavigationItem extends StatelessWidget {
  const _GroupNavigationItem({
    required this.group,
    required this.selected,
    required this.onActivate,
    required this.focusNode,
    required this.onPrevious,
    required this.onNext,
    this.label,
    this.icon,
    this.mark,
    required this.keyPrefix,
  });

  final OverlayGroupMark? mark;
  final String group;
  final bool selected;
  final ValueChanged<InteractionSource> onActivate;
  final FocusNode focusNode;
  final VoidCallback onPrevious, onNext;
  final String? label;
  final StarBridgeIconSemantic? icon;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = selected
        ? tokens.colors.accent
        : tokens.colors.textSecondary;
    final data = InteractionScope.of(context);
    final native = data.suite == InteractionSuite.standard;
    final copy = label ?? overlayWorkspaceGroupName(context, group);
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Ink(
        decoration: BoxDecoration(
          color: native && selected
              ? tokens.colors.accentSoft
              : Colors.transparent,
          border: BorderDirectional(
            start: BorderSide(
              color: native && selected
                  ? tokens.colors.accent
                  : Colors.transparent,
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
            StarBridgeIcon(icon ?? _groupIcon(group), size: 18, color: accent),
            SizedBox(width: tokens.space.sm),
            Expanded(
              child: Text(
                copy,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? tokens.colors.textPrimary : accent,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (mark?.ownSource == true)
              Container(
                key: Key('$keyPrefix-own-source-$group'),
                width: 7,
                height: 7,
                margin: EdgeInsetsDirectional.only(start: tokens.space.xs),
                decoration: BoxDecoration(
                  color: tokens.colors.warning,
                  shape: BoxShape.circle,
                ),
              ),
            if (mark?.off == true)
              Padding(
                padding: EdgeInsetsDirectional.only(start: tokens.space.xs),
                child: Text(
                  _copy(context, 'overlay.workspace.groupOff'),
                  key: Key('$keyPrefix-off-$group'),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: tokens.colors.textDisabled),
                ),
              ),
          ],
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp): onPrevious,
        const SingleActivator(LogicalKeyboardKey.arrowDown): onNext,
        if (native)
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.numpadEnter,
            LogicalKeyboardKey.space,
          ])
            SingleActivator(key): () => onActivate(InteractionSource.keyboard),
      },
      child: AnimatedBuilder(
        animation: focusNode,
        builder: (context, _) => Material(
          type: MaterialType.transparency,
          child: native
              ? Semantics(
                  button: true,
                  selected: selected,
                  focused: focusNode.hasFocus,
                  label: copy,
                  excludeSemantics: true,
                  onTap: () => onActivate(InteractionSource.keyboard),
                  child: InkWell(
                    key: Key('$keyPrefix-nav-$group'),
                    excludeFromSemantics: true,
                    focusNode: focusNode,
                    onTap: () => onActivate(InteractionSource.pointer),
                    hoverColor: tokens.colors.accent.withValues(alpha: 0.08),
                    focusColor: tokens.colors.accent.withValues(alpha: 0.10),
                    highlightColor: tokens.colors.accent.withValues(
                      alpha: 0.12,
                    ),
                    splashColor: tokens.colors.accent.withValues(alpha: 0.22),
                    splashFactory: data.reduceMotion
                        ? NoSplash.splashFactory
                        : null,
                    child: body,
                  ),
                )
              : SuitePressable(
                  key: Key('$keyPrefix-nav-$group'),
                  kind: PressableKind.navItem,
                  baseRadius: 0,
                  semanticSelected: selected,
                  semanticFocused: focusNode.hasFocus,
                  semanticLabel: copy,
                  excludeChildSemantics: true,
                  focusNode: focusNode,
                  onActivate: onActivate,
                  child: body,
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
