import '../common/user_avatar_menu.dart';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_members_models.dart';

class OfficialFleetMemberTableHeader extends StatelessWidget {
  const OfficialFleetMemberTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: tokens.colors.textSecondary);
    return Container(
      padding: EdgeInsetsDirectional.fromSTEB(
        tokens.space.sm + 3,
        tokens.space.sm,
        tokens.space.sm,
        tokens.space.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.surfaces.panel.border,
            width: tokens.stroke.hairline,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 48),
          SizedBox(width: tokens.space.md),
          Expanded(
            flex: 3,
            child: Text(
              strings.text('officialFleet.members.column.member'),
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              strings.text('officialFleet.members.column.server'),
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              strings.text('officialFleet.members.column.rank'),
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              strings.text('officialFleet.members.column.ship'),
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              strings.text('officialFleet.members.column.location'),
              style: style,
            ),
          ),
          Expanded(
            child: Text(
              strings.text('officialFleet.members.column.presence'),
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class OfficialFleetMemberRow extends StatelessWidget {
  const OfficialFleetMemberRow({
    required this.member,
    required this.wide,
    required this.onOpen,
    super.key,
  });

  final OfficialFleetMember member;
  final bool wide;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final presenceColor = _presenceColor(tokens, member.presence);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: member.presence == OfficialFleetMemberPresence.inGame
            ? Color.alphaBlend(
                tokens.colors.success.withValues(alpha: 0.08),
                tokens.surfaces.raised.fill,
              )
            : tokens.surfaces.raised.fill,
        border: Border.all(
          color: tokens.surfaces.raised.border,
          width: tokens.stroke.hairline,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            children: [
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: presenceColor),
              ),
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  tokens.space.sm + 3,
                  tokens.space.sm,
                  tokens.space.sm,
                  tokens.space.sm,
                ),
                child: wide
                    ? _WideMemberRow(member: member)
                    : _CompactMemberRow(member: member),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideMemberRow extends StatelessWidget {
  const _WideMemberRow({required this.member});

  final OfficialFleetMember member;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MemberAvatar(member: member),
        SizedBox(width: context.tokens.space.md),
        Expanded(flex: 3, child: _MemberIdentity(member: member)),
        Expanded(flex: 2, child: _ValueText(field: member.server)),
        Expanded(flex: 2, child: _OfficialRank(member: member)),
        Expanded(flex: 2, child: _ValueText(field: member.ship)),
        Expanded(
          flex: 2,
          child: _LocationValue(
            field: member.location,
            arrivalPending: member.arrivalPending,
          ),
        ),
        Expanded(child: _PresenceValue(presence: member.presence)),
      ],
    );
  }
}

class _CompactMemberRow extends StatelessWidget {
  const _CompactMemberRow({required this.member});

  final OfficialFleetMember member;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _MemberAvatar(member: member),
            SizedBox(width: tokens.space.md),
            Expanded(child: _MemberIdentity(member: member)),
            _PresenceValue(presence: member.presence),
          ],
        ),
        SizedBox(height: tokens.space.md),
        Wrap(
          spacing: tokens.space.lg,
          runSpacing: tokens.space.sm,
          children: [
            _CompactField(
              label: strings.text('officialFleet.members.column.server'),
              child: _ValueText(field: member.server),
            ),
            _CompactField(
              label: strings.text('officialFleet.members.column.rank'),
              child: _OfficialRank(member: member),
            ),
            _CompactField(
              label: strings.text('officialFleet.members.column.ship'),
              child: _ValueText(field: member.ship),
            ),
            _CompactField(
              label: strings.text('officialFleet.members.column.location'),
              child: _LocationValue(
                field: member.location,
                arrivalPending: member.arrivalPending,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: context.tokens.colors.textSecondary),
          ),
          SizedBox(height: context.tokens.space.xxs),
          child,
        ],
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member});

  final OfficialFleetMember member;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fallback = ColoredBox(
      color: tokens.surfaces.selected.fill,
      child: Center(
        child: Text(
          member.callsign.isEmpty
              ? '?'
              : member.callsign.characters.first.toUpperCase(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
    return UserAvatarMenu(
      name: member.callsign,
      child: Container(
        width: 48,
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          border: Border.all(color: tokens.surfaces.raised.border),
          borderRadius: tokens.shape.small,
        ),
        child: member.avatarUrl == null
            ? fallback
            : Image.network(
                member.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _MemberIdentity extends StatelessWidget {
  const _MemberIdentity({required this.member});

  final OfficialFleetMember member;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          member.callsign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (member.callsign != member.gameId) ...[
          SizedBox(height: tokens.space.xxs),
          Text(
            '(${member.gameId})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _OfficialRank extends StatelessWidget {
  const _OfficialRank({required this.member});

  final OfficialFleetMember member;

  @override
  Widget build(BuildContext context) {
    final command = context.tokens.domainColors.command;
    final label = [
      if (member.officialRankName?.trim().isNotEmpty ?? false)
        member.officialRankName!,
      if (member.officialRankValue case final int rank
          when rank >= 1 && rank <= 5)
        '$rank★',
    ].join(' · ');
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.tokens.space.sm,
          vertical: context.tokens.space.xxs,
        ),
        decoration: BoxDecoration(
          color: command.soft,
          border: Border.all(color: command.foreground.withValues(alpha: 0.65)),
          borderRadius: context.tokens.shape.small,
        ),
        child: Text(
          label.isEmpty
              ? AppStrings.of(context).text('officialFleet.rank.unknown')
              : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: command.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// Details reuse only the current viewer-scoped row. No hidden profile fetch or
// contact/management action is inferred from membership or rank.
class OfficialFleetMemberDetails extends StatelessWidget {
  const OfficialFleetMemberDetails({
    required this.member,
    required this.onClose,
    super.key,
  });

  final OfficialFleetMember member;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final space = context.tokens.space;
    return StarBridgeSurface(
      key: const Key('official-fleet-member-details'),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('official-fleet-member-details-close'),
              onPressed: onClose,
              child: Text(strings.text('officialFleet.members.details.back')),
            ),
          ),
          Text(
            strings.text('officialFleet.members.details.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: space.md),
          Text(member.callsign, style: Theme.of(context).textTheme.titleSmall),
          if (member.callsign != member.gameId) Text('(${member.gameId})'),
          SizedBox(height: space.md),
          _OfficialRank(member: member),
          SizedBox(height: space.md),
          Text(
            strings.text(switch (member.starBridgeConnected) {
              true => 'officialFleet.members.connection.connected',
              false => 'officialFleet.members.field.notConnected',
              null => 'officialFleet.members.connection.unknown',
            }),
          ),
          SizedBox(height: space.md),
          _PresenceValue(presence: member.presence),
          for (final entry in <String, OfficialFleetMemberField>{
            'server': member.server,
            'ship': member.ship,
            'location': member.location,
          }.entries) ...[
            SizedBox(height: space.md),
            Text(
              strings.text('officialFleet.members.column.${entry.key}'),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            SizedBox(height: space.xxs),
            Text(_fieldText(strings, entry.value)),
          ],
          if (member.arrivalPending)
            Text(strings.text('officialFleet.members.arrivalPending')),
        ],
      ),
    );
  }
}

class _ValueText extends StatelessWidget {
  const _ValueText({required this.field});

  final OfficialFleetMemberField field;

  @override
  Widget build(BuildContext context) {
    return Text(
      _fieldText(AppStrings.of(context), field),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: field.state == OfficialFleetMemberFieldState.value
            ? context.tokens.colors.textPrimary
            : context.tokens.colors.textSecondary,
      ),
    );
  }
}

class _LocationValue extends StatelessWidget {
  const _LocationValue({required this.field, required this.arrivalPending});

  final OfficialFleetMemberField field;
  final bool arrivalPending;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: _ValueText(field: field)),
        if (arrivalPending) ...[
          SizedBox(width: context.tokens.space.xs),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.tokens.space.xs,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: context.tokens.colors.warningSoft,
              border: Border.all(color: context.tokens.colors.warning),
              borderRadius: context.tokens.shape.small,
            ),
            child: Text(
              AppStrings.of(context)
                  .text('officialFleet.members.arrivalPending'),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: context.tokens.colors.warning),
            ),
          ),
        ],
      ],
    );
  }
}

class _PresenceValue extends StatelessWidget {
  const _PresenceValue({required this.presence});

  final OfficialFleetMemberPresence presence;

  @override
  Widget build(BuildContext context) {
    final color = _presenceColor(context.tokens, presence);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: context.tokens.icons.statusDot,
          height: context.tokens.icons.statusDot,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: context.tokens.space.xs),
        Flexible(
          child: Text(
            AppStrings.of(context).text(_presenceLabelKey(presence)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

String _presenceLabelKey(
  OfficialFleetMemberPresence presence,
) => switch (presence) {
  OfficialFleetMemberPresence.unknown =>
    'officialFleet.members.presence.unknown',
  OfficialFleetMemberPresence.away => 'officialFleet.members.presence.away',
  OfficialFleetMemberPresence.notConnected =>
    'officialFleet.members.presence.notConnected',
  OfficialFleetMemberPresence.offline =>
    'officialFleet.members.presence.offline',
  OfficialFleetMemberPresence.online => 'officialFleet.members.presence.online',
  OfficialFleetMemberPresence.inGame => 'officialFleet.members.presence.inGame',
  OfficialFleetMemberPresence.invisible =>
    'officialFleet.members.presence.invisible',
};

Color _presenceColor(
  StarBridgeTokens tokens,
  OfficialFleetMemberPresence presence,
) => switch (presence) {
  OfficialFleetMemberPresence.unknown => tokens.colors.textDisabled,
  OfficialFleetMemberPresence.away => tokens.colors.warning,
  OfficialFleetMemberPresence.notConnected => tokens.colors.textDisabled,
  OfficialFleetMemberPresence.offline => tokens.colors.offline,
  OfficialFleetMemberPresence.online => tokens.colors.info,
  OfficialFleetMemberPresence.inGame => tokens.colors.success,
  OfficialFleetMemberPresence.invisible => tokens.colors.warning,
};

String _fieldText(AppStrings strings, OfficialFleetMemberField field) =>
    switch (field.state) {
      OfficialFleetMemberFieldState.value =>
        field.value ?? strings.text('officialFleet.members.field.unknown'),
      OfficialFleetMemberFieldState.unknown => strings.text(
        'officialFleet.members.field.unknown',
      ),
      OfficialFleetMemberFieldState.notShared => strings.text(
        'officialFleet.members.field.notShared',
      ),
      OfficialFleetMemberFieldState.notInGame => strings.text(
        'officialFleet.members.field.notInGame',
      ),
      OfficialFleetMemberFieldState.restricted => strings.text(
        'officialFleet.members.field.restricted',
      ),
      OfficialFleetMemberFieldState.notConnected => strings.text(
        'officialFleet.members.field.notConnected',
      ),
    };
