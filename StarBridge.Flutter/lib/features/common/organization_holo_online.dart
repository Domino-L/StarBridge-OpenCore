import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'organization_holo.dart';

/// One member in the holo "online now" column (user decision 2026-10-29,
/// option B: both holo chat sections keep the online column on the left).
class OrganizationHoloOnlineMember {
  const OrganizationHoloOnlineMember({
    required this.key,
    required this.name,
    required this.detail,
    required this.dot,
    required this.avatar,
  });

  final Key key;
  final String name, detail;
  final Color dot;

  /// The member's own avatar; it keeps its shape (user decision 2026-10-22).
  final Widget avatar;
}

class OrganizationHoloOnlineGroup {
  const OrganizationHoloOnlineGroup(this.label, this.members);
  final String label;
  final List<OrganizationHoloOnlineMember> members;
}

/// Keys the two owners already expose to their tests and callers.
class OrganizationHoloOnlineKeys {
  const OrganizationHoloOnlineKeys({
    this.pane,
    this.list,
    this.status,
    this.toggle,
    this.allMembers,
    this.close,
  });
  final Key? pane, list, status, toggle, allMembers, close;
}

/// The expanded column: no frame, a hairline on its chat side, members
/// grouped by state with a square dot and their detail.
class OrganizationHoloOnlineColumn extends StatelessWidget {
  const OrganizationHoloOnlineColumn({
    required this.title,
    required this.groups,
    this.keys = const OrganizationHoloOnlineKeys(),
    this.count,
    this.status,
    this.progress,
    this.trailing = const [],
    this.footer = const [],
    this.toggleLabel,
    this.onToggle,
    this.allMembersLabel,
    this.onAllMembers,
    super.key,
  });

  final String title;
  final String? count, status, toggleLabel, allMembersLabel;
  final List<OrganizationHoloOnlineGroup> groups;
  final OrganizationHoloOnlineKeys keys;
  final Widget? progress;
  final List<Widget> trailing, footer;
  final VoidCallback? onToggle, onAllMembers;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final mono = text.labelSmall?.copyWith(
      fontFamily: tokens.typography.monoFamily,
      letterSpacing: 3,
      color: tokens.colors.textDisabled,
    );
    return Container(
      key: keys.pane,
      padding: const EdgeInsetsDirectional.only(end: 14),
      decoration: BoxDecoration(
        border: BorderDirectional(
          end: BorderSide(color: OrganizationHoloColors(context).hair),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                Text(
                  count!,
                  style: text.labelMedium?.copyWith(
                    color: tokens.colors.textSecondary,
                  ),
                ),
              ],
              const Spacer(),
              ...trailing,
              if (onToggle != null)
                StarBridgeIconAction(
                  controlKey: keys.toggle,
                  label: toggleLabel ?? title,
                  onActivate: (_) => onToggle!(),
                  icon: const StandardIcon(
                    StandardIconSemantic.chevronLeft,
                    size: 18,
                  ),
                ),
            ],
          ),
          ?progress,
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                status!,
                key: keys.status,
                style: text.bodySmall?.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
            ),
          Expanded(
            child: ListView(
              key: keys.list,
              primary: false,
              children: [
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 6),
                    child: Text(group.label, style: mono),
                  ),
                  for (final member in group.members)
                    _MemberRow(member: member),
                ],
              ],
            ),
          ),
          ...footer,
          if (onAllMembers != null) ...[
            Divider(height: 1, color: OrganizationHoloColors(context).hair),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StarBridgeActionButton(
                key: keys.allMembers,
                kind: StarBridgeActionKind.quiet,
                onActivate: (_) => onAllMembers!(),
                child: Text('${allMembersLabel ?? ''} ›'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});
  final OrganizationHoloOnlineMember member;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    return Padding(
      key: member.key,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox.square(dimension: 28, child: member.avatar),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsetsDirectional.only(end: 6),
                      color: member.dot,
                    ),
                    Expanded(
                      child: Text(
                        member.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: tokens.colors.textDisabled,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The collapsed rail: the expand control, then avatars with their state
/// dot beside them (never over the avatar), then the count.
class OrganizationHoloOnlineRail extends StatelessWidget {
  const OrganizationHoloOnlineRail({
    required this.label,
    required this.members,
    required this.onExpand,
    this.count,
    this.keys = const OrganizationHoloOnlineKeys(),
    super.key,
  });

  final String label;
  final String? count;
  final List<OrganizationHoloOnlineMember> members;
  final VoidCallback onExpand;
  final OrganizationHoloOnlineKeys keys;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      key: keys.pane,
      decoration: BoxDecoration(
        border: BorderDirectional(
          end: BorderSide(color: OrganizationHoloColors(context).hair),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Only whole avatars: the rest are behind the count.
          final room = ((box.maxHeight - 96) / 36).floor();
          final shown = members.take(room < 0 ? 0 : room);
          return Column(
            children: [
              StarBridgeIconAction(
                controlKey: keys.toggle,
                label: label,
                onActivate: (_) => onExpand(),
                icon: const StandardIcon(StandardIconSemantic.people, size: 20),
              ),
              const SizedBox(height: 6),
              for (final member in shown)
                Padding(
                  key: member.key,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox.square(dimension: 28, child: member.avatar),
                      const SizedBox(width: 3),
                      Container(width: 6, height: 6, color: member.dot),
                    ],
                  ),
                ),
              if (count != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    count!,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

typedef OrganizationHoloOnlineBuilder = Widget Function(
  BuildContext context, {
  required bool collapsed,
  VoidCallback? onToggle,
});

/// Holo chat layout: the online column on the left, the conversation on the
/// right. The column collapses to a rail; narrow windows keep the rail and
/// open the full column in a dialog.
class OrganizationHoloChatDock extends StatefulWidget {
  const OrganizationHoloChatDock({
    required this.online,
    required this.chat,
    this.closeKey,
    this.resetKey,
    super.key,
  });

  final OrganizationHoloOnlineBuilder online;
  final Widget chat;
  final Key? closeKey;

  /// A new value (another organization) expands the column again.
  final Object? resetKey;

  static const expandedWidth = 240.0, railWidth = 44.0;

  @override
  State<OrganizationHoloChatDock> createState() => _DockState();
}

class _DockState extends State<OrganizationHoloChatDock> {
  bool _collapsed = false;
  StarBridgeDialogRoute<void>? _route;

  @override
  void didUpdateWidget(covariant OrganizationHoloChatDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _dismiss();
      _collapsed = false;
    }
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  void _dismiss() {
    final route = _route;
    _route = null;
    scheduleMicrotask(() {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
  }

  Future<void> _openNarrow() async {
    if (_route != null) return;
    StarBridgeDialogRoute<void>? opened;
    await showStarBridgeDialog<void>(
      context,
      source: InteractionSource.pointer,
      onRouteCreated: (route) => _route = opened = route,
      builder: (dialogContext) => AlertDialog(
        content: SizedBox(
          width: 280,
          height: 480,
          child: OrganizationHolo(
            child: widget.online(dialogContext, collapsed: false),
          ),
        ),
        actions: [
          StarBridgeActionButton(
            key: widget.closeKey,
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) =>
                dismissStarBridgeDialog<void>(dialogContext, source: source),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
    if (_route == opened) _route = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final narrow = size.maxWidth < 900;
      final collapsed = narrow || _collapsed;
      final target = collapsed
          ? OrganizationHoloChatDock.railWidth
          : OrganizationHoloChatDock.expandedWidth;
      final reduce = resolveStarBridgeInteraction(context).reduceMotion;
      final column = widget.online(
        context,
        collapsed: collapsed,
        onToggle: narrow
            ? _openNarrow
            : () => setState(() => _collapsed = !_collapsed),
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: target),
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            builder: (context, width, child) => SizedBox(
              width: width,
              child: ClipRect(
                child: OverflowBox(
                  alignment: AlignmentDirectional.topStart,
                  minWidth: target,
                  maxWidth: target,
                  child: child,
                ),
              ),
            ),
            child: column,
          ),
          const SizedBox(width: 16),
          Expanded(child: widget.chat),
        ],
      );
    },
  );
}
