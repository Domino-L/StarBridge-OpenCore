import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'organization_holo.dart';
import 'organization_member_copy.dart';
import 'organization_member_runtime_cells.dart';
import 'user_avatar_menu.dart';
export 'organization_member_runtime_cells.dart';

enum OrganizationMemberPresence { unknown, offline, online, away, inGame }

enum OrganizationMemberFilter { all, online, inGame }

class OrganizationMemberColumns {
  const OrganizationMemberColumns({
    this.presence = false,
    this.server = false,
    this.ship = false,
    this.location = false,
  });
  const OrganizationMemberColumns.all()
    : presence = true,
      server = true,
      ship = true,
      location = true;
  final bool presence, server, ship, location;
  List<String> get keys => [
    'member',
    'role',
    if (server) 'server',
    if (ship) 'ship',
    if (location) 'location',
    if (presence) 'presence',
  ];
}

class OrganizationMemberEntry {
  const OrganizationMemberEntry({
    required this.reference,
    required this.identity,
    required this.role,
    this.roleColor,
    this.presence = OrganizationMemberPresence.unknown,
    this.runtime = const MemberRuntimeCells.empty(),
    this.actions,
  });
  final String reference, role;
  final MemberRuntimeCells runtime;
  String get server => runtime.server.text;
  String get ship => runtime.ship.text;
  String get location => runtime.location.text;
  final Widget identity;
  final Color? roleColor;
  final OrganizationMemberPresence presence;
  final Widget? actions;
}

/// A single geometry and column order for both organizations and menu surfaces.
class OrganizationMemberRow extends StatelessWidget {
  const OrganizationMemberRow({
    required this.entry,
    required this.columns,
    required this.roleLabel,
    this.showActions = false,
    super.key,
  });
  final OrganizationMemberEntry entry;
  final OrganizationMemberColumns columns;
  final String roleLabel;
  final bool showActions;
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final holo = OrganizationHolo.of(context);
    final presence = _visiblePresence(entry.presence);
    final notInGame = MemberRuntimeCell.placeholder(
      memberBoardText(context, 'notInGame'),
    );
    final runtime = presence == OrganizationMemberPresence.inGame
        ? entry.runtime
        : MemberRuntimeCells(
            server: notInGame,
            ship: notInGame,
            location: notInGame,
          );
    final cells = <String, Widget>{
      'member': entry.identity,
      'role': OrganizationMemberRoleBadge(
        label: entry.role,
        color: entry.roleColor,
      ),
      'presence': OrganizationMemberStatus(presence: presence),
      'server': Text(runtime.server.text),
      'ship': Text(runtime.ship.text),
      'location': Text(runtime.location.text),
    };
    final row = Container(
      decoration: holo
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: OrganizationHoloColors(context).hair),
              ),
            )
          : BoxDecoration(
              color: tokens.surfaces.raised.fill,
              border: Border.all(
                color: tokens.surfaces.panel.border,
                width: tokens.stroke.hairline,
              ),
              borderRadius: tokens.shape.small,
            ),
      child: Stack(
        children: [
          if (columns.presence)
            PositionedDirectional(
              start: holo ? 4 : 0,
              top: holo ? 14 : 8,
              bottom: holo ? 14 : 8,
              width: holo ? 3 : tokens.space.xxs,
              child: ColoredBox(color: _presenceColor(context, presence)),
            ),
          Padding(
            padding: holo
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                : const EdgeInsets.all(16),
            child: Material(
              color: Colors.transparent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final layout = _MemberColumnLayout(
                    context,
                    columns,
                    constraints.maxWidth,
                    showActions,
                  );
                  if (layout.fits) {
                    return Row(
                      children: [
                        for (final key in columns.keys)
                          layout.cell(key, cells[key]!),
                        const Spacer(),
                        if (showActions)
                          SizedBox(
                            width: layout.actionWidth,
                            child: entry.actions ?? const SizedBox.shrink(),
                          ),
                      ],
                    );
                  }
                  Widget compactCell(String key, Widget value) => SizedBox(
                    width: ((constraints.maxWidth - 16) / 2).clamp(0, 180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (key.isNotEmpty) ...[
                          Text(
                            key == 'role'
                                ? roleLabel
                                : memberBoardText(context, key),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.colors.textSecondary),
                          ),
                          const SizedBox(height: 4),
                        ],
                        value,
                      ],
                    ),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: cells['member']!),
                          if (showActions)
                            entry.actions ??
                                SizedBox(width: layout.actionWidth),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          for (final key in columns.keys.skip(1))
                            compactCell(key, cells[key]!),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
    return holo ? _HoloHover(child: row) : row;
  }
}

/// A holo row lights up from its start edge under the pointer.
class _HoloHover extends StatefulWidget {
  const _HoloHover({required this.child});

  final Widget child;

  @override
  State<_HoloHover> createState() => _HoloHoverState();
}

class _HoloHoverState extends State<_HoloHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.colors.accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _hover
              ? LinearGradient(
                  colors: [
                    accent.withValues(alpha: .10),
                    accent.withValues(alpha: .02),
                  ],
                )
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

OrganizationMemberPresence _visiblePresence(OrganizationMemberPresence value) =>
    value == OrganizationMemberPresence.unknown
    ? OrganizationMemberPresence.offline
    : value;

Color _presenceColor(
  BuildContext context,
  OrganizationMemberPresence presence,
) => switch (presence) {
  OrganizationMemberPresence.inGame => context.tokens.colors.success,
  OrganizationMemberPresence.online => context.tokens.colors.info,
  OrganizationMemberPresence.away => context.tokens.colors.warning,
  OrganizationMemberPresence.offline => context.tokens.colors.offline,
  _ => context.tokens.colors.textSecondary,
};

// The same visible-column plan lays out both headings and rows. Identity and
// role stay bounded and aligned when unsupported runtime columns are removed.
class _MemberColumnLayout {
  _MemberColumnLayout(
    BuildContext context,
    this.columns,
    this.available,
    this.actions,
  ) : gap = 12,
      actionWidth = context.tokens.density.controlHeight,
      scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final OrganizationMemberColumns columns;
  final double available, gap, actionWidth, scale;
  final bool actions;
  double get memberWidth => 260 * scale;
  double get roleWidth => 140 * scale;
  double _minimum(String key) => switch (key) {
    'member' => memberWidth,
    'role' => roleWidth,
    'presence' => 80 * scale,
    'server' => 100 * scale,
    'ship' => 120 * scale,
    _ => 140 * scale,
  };
  double get minimum =>
      columns.keys.fold<double>(0, (sum, key) => sum + _minimum(key) + gap) +
      (actions ? actionWidth : 0);
  bool get fits =>
      available >= (columns.keys.length == 6 ? 800 * scale : minimum);
  double extent(String key) {
    // Original community proportions, referenced to all supported fields.
    // Hiding fields removes their width instead of redistributing it.
    final fullMinimum =
        const OrganizationMemberColumns.all().keys.fold<double>(
          0,
          (sum, key) => sum + _minimum(key) + gap,
        ) +
        (actions ? actionWidth : 0);
    final reference =
        (columns.keys.length < 6 && available < fullMinimum
            ? fullMinimum
            : available) -
        (actions ? actionWidth : 0);
    final weight = switch (key) {
      'member' => 28,
      'role' || 'server' || 'presence' => 14,
      'ship' => 18,
      _ => 16,
    };
    return reference * weight / 104;
  }

  Widget cell(String key, Widget child) => SizedBox(
    width: extent(key),
    child: Padding(
      padding: EdgeInsetsDirectional.only(end: gap),
      child: child,
    ),
  );
}

class OrganizationMemberHeader extends StatelessWidget {
  const OrganizationMemberHeader({
    required this.columns,
    required this.roleLabel,
    this.showActions = false,
    super.key,
  });
  final OrganizationMemberColumns columns;
  final String roleLabel;
  final bool showActions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final layout = _MemberColumnLayout(
          context,
          columns,
          constraints.maxWidth,
          showActions,
        );
        if (!layout.fits) {
          return const SizedBox.shrink();
        }
        final holo = OrganizationHolo.of(context);
        final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: context.tokens.colors.textSecondary,
          letterSpacing: holo ? 2 : null,
        );
        // Holo boards draw the full-width hairline under the heading.
        final heading = Padding(
          padding: holo
              ? const EdgeInsets.only(top: 12, bottom: 8)
              : const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final key in columns.keys)
                layout.cell(
                  key,
                  Text(
                    key == 'role' ? roleLabel : memberBoardText(context, key),
                    style: style,
                  ),
                ),
              const Spacer(),
              if (showActions)
                SizedBox(
                  width: layout.actionWidth,
                  child: Text(
                    memberBoardText(context, 'actions'),
                    style: style,
                  ),
                ),
            ],
          ),
        );
        return heading;
      },
    ),
  );
}

class OrganizationMemberRoleBadge extends StatelessWidget {
  const OrganizationMemberRoleBadge({
    required this.label,
    this.color,
    super.key,
  });
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.tokens.space.xs,
        vertical: context.tokens.space.xxs,
      ),
      decoration: OrganizationHolo.of(context)
          ? ShapeDecoration(
              color: color?.withValues(alpha: .08),
              shape: OrganizationHoloBorder(
                cut: 5,
                side: BorderSide(
                  color:
                      color?.withValues(alpha: .6) ??
                      context.tokens.colors.textPrimary.withValues(alpha: .32),
                ),
              ),
            )
          : BoxDecoration(
              color: color?.withValues(alpha: .08),
              border: Border.all(
                color:
                    color?.withValues(alpha: .6) ??
                    context.tokens.surfaces.panel.border,
              ),
            ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: color ?? context.tokens.colors.textPrimary),
      ),
    ),
  );
}

class OrganizationMemberStatus extends StatelessWidget {
  const OrganizationMemberStatus({required this.presence, super.key});
  final OrganizationMemberPresence presence;
  @override
  Widget build(BuildContext context) {
    final visible = _visiblePresence(presence);
    final color = _presenceColor(context, visible);
    final label = Text(
      memberBoardText(
        context,
        visible == OrganizationMemberPresence.online
            ? 'appOnline'
            : visible.name,
      ),
      style: TextStyle(color: color),
    );
    if (!OrganizationHolo.of(context)) return label;
    return Row(
      children: [
        SizedBox.square(dimension: 7, child: ColoredBox(color: color)),
        const SizedBox(width: 8),
        Flexible(child: label),
      ],
    );
  }
}

/// Only the identity is interactive; an absent trusted target creates no menu,
/// hover affordance, disabled action, or lookup by display name.
class OrganizationMemberIdentity extends StatelessWidget {
  const OrganizationMemberIdentity({
    required this.name,
    required this.avatar,
    this.gameId = '',
    this.isSelf = false,
    this.target,
    this.includeSocialActions = true,
    this.avatarImageData,
    this.avatarBytes,
    this.actions = const [],
    super.key,
  });
  final String name, gameId;
  final Widget avatar;
  final bool isSelf, includeSocialActions;
  final UserTarget? target;
  final String? avatarImageData;
  final Uint8List? avatarBytes;
  final List<AvatarMenuAction> actions;
  @override
  Widget build(BuildContext context) {
    final holo = OrganizationHolo.of(context);
    final identity = Row(
      crossAxisAlignment: holo
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        SizedBox.square(dimension: holo ? 36 : 48, child: avatar),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name${isSelf ? ' · ${memberBoardText(context, 'self')}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (gameId.isNotEmpty && gameId != name)
                Text(
                  gameId,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: holo
                      ? Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.tokens.colors.textSecondary,
                        )
                      : Theme.of(context).textTheme.bodyMedium,
                ),
            ],
          ),
        ),
      ],
    );
    if (target == null) return identity;
    return UserAvatarMenu(
      name: name,
      target: target,
      isSelf: isSelf,
      includeSocialActions: includeSocialActions,
      avatarImageData: avatarImageData,
      avatarBytes: avatarBytes,
      actions: actions,
      child: identity,
    );
  }
}
