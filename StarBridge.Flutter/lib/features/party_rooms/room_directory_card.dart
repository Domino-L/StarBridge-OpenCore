import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'party_rooms_module.dart';
import 'room_action_dialogs.dart';
import 'room_display.dart';
import 'room_member_policy.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';

/// Every join decision is visible in the list. No permanent preview column,
/// and no member location/ship/shard telemetry before joining.
class RoomDirectoryCard extends StatelessWidget {
  const RoomDirectoryCard({
    super.key,
    required this.room,
    required this.serverTime,
    required this.selected,
    required this.onSelect,
    required this.onJoin,
    required this.supportsCommands,
  });
  final PartyRoom room;
  final DateTime serverTime;
  final bool selected, supportsCommands;
  final VoidCallback? onSelect;
  final ValueChanged<InteractionSource>? onJoin;
  @override
  Widget build(BuildContext context) {
    String t(String key) => roomText(context, key);
    final colors = context.tokens.colors;
    final host = room.members.where((item) => item.isHost).firstOrNull;
    final full = room.members.length >= room.capacity;
    final closed = roomRecruitmentClosed(room, serverTime);
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.zero,
      child: StarBridgeInteractionRegion(
        child: Material(
          type: MaterialType.transparency,
          // This target contains independent Join/avatar actions. A disabled
          // selection must disable only this row, never its descendants.
          child: SuitePressable(
            key: ValueKey('room-${room.id}'),
            kind: PressableKind.row,
            baseRadius: 6,
            semanticLabel: room.title,
            semanticSelected: selected,
            onActivate: onSelect == null
                ? null
                : (source) => unawaited(
                    runStarBridgeActivation<void>(source, onSelect!),
                  ),
            // Keep the card's existing text/icon treatment. The row supplies
            // interaction feedback, not a second selected fill or disabled veil.
            child: IconTheme(
              data: IconTheme.of(context),
              child: DefaultTextStyle.merge(
                style: DefaultTextStyle.of(context).style,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: selected
                            ? colors.accent
                            : colors.textSecondary.withValues(alpha: .2),
                        width: 3,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ExcludeSemantics(
                                  child: Text(
                                    room.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                Text(
                                  '${t('host')} · ${host?.callsign.trim().isNotEmpty == true ? host!.callsign : t('hostIdentityPrivate')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                                if (host != null &&
                                    host.presenceKey != 'presence.inGame')
                                  Text(
                                    t(
                                      host.presenceKey == 'presence.unknown'
                                          ? 'hostGameStateUnknown'
                                          : 'hostNotInGame',
                                    ),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: colors.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '${room.members.length} / ${room.capacity}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontFamily:
                                      context.tokens.typography.monoFamily,
                                  color: full && !closed
                                      ? colors.warning
                                      : colors.textPrimary,
                                ),
                          ),
                          const SizedBox(width: 16),
                          if (closed || full)
                            Text(
                              t(closed ? 'closed' : 'full'),
                              style: TextStyle(
                                color: closed ? colors.offline : colors.warning,
                              ),
                            )
                          else if (supportsCommands)
                            StarBridgeActionButton(
                              controlKey: ValueKey('room-join-${room.id}'),
                              onActivate: onJoin,
                              child: Text(
                                roomActionText(
                                  context,
                                  room.admissionMode == 'approval'
                                      ? 'apply'
                                      : 'join',
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (room.goal.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          room.goal,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final details = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RoomJoinFacts(room: room),
                              if (room.tags.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                RoomTags(room: room),
                              ],
                            ],
                          );
                          final avatars = RoomMemberPreview(room: room);
                          return constraints.maxWidth >= 820
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(child: details),
                                    const SizedBox(width: 24),
                                    SizedBox(width: 320, child: avatars),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    details,
                                    const SizedBox(height: 14),
                                    avatars,
                                  ],
                                );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoomMemberPreview extends StatelessWidget {
  const RoomMemberPreview({super.key, required this.room});
  final PartyRoom room;
  @override
  Widget build(BuildContext context) {
    final permitted =
        room.canPreviewMemberProfiles &&
        !room.passwordRequired &&
        const {'direct', 'approval'}.contains(room.admissionMode) &&
        const {'everyone', 'friends', 'fleet'}.contains(room.eligibility);
    final locked = roomText(context, 'profilesPrivate');
    if (!permitted) {
      return Row(
        key: const Key('room-member-preview-locked'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const StarBridgeIcon(StarBridgeIconSemantic.privacy, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              locked,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.tokens.colors.textSecondary),
            ),
          ),
        ],
      );
    }
    return Wrap(
      key: const Key('room-member-preview'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final member in room.members)
          if (member.userRef == null)
            StarBridgeTooltip(
              message: locked,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: StarBridgeIcon(
                    StarBridgeIconSemantic.privacy,
                    size: 18,
                    color: context.tokens.colors.textSecondary,
                  ),
                ),
              ),
            )
          else
            RoomIdentityAvatar(
              name: member.callsign,
              avatarData: member.avatarData,
              userRef: member.userRef,
              size: 40,
              includeSocialActions: false,
              includeNameInHint: true,
            ),
      ],
    );
  }
}

class RoomJoinFacts extends StatelessWidget {
  const RoomJoinFacts({required this.room, super.key});
  final PartyRoom room;
  @override
  Widget build(BuildContext context) {
    String t(String key) => roomText(context, key);
    final host = room.members.where((member) => member.isHost).firstOrNull;
    final hostInGame = host?.presenceKey == 'presence.inGame';
    return Wrap(
      spacing: 30,
      runSpacing: 10,
      children: [
        RoomFact(
          t('language'),
          roomChoice(context, 'language', room.language),
          emphasis: true,
        ),
        if (hostInGame && room.leaderServerRegion.isNotEmpty)
          RoomFact(
            t('leaderServer'),
            roomRegion(context, room),
            emphasis: true,
          ),
        if (hostInGame && room.leaderGameVersion.isNotEmpty)
          RoomFact(t('leaderVersion'), room.leaderGameVersion, emphasis: true),
        RoomFact(
          t('admission'),
          roomChoice(context, 'admission', room.admissionMode),
        ),
        RoomFact(t('voice'), roomChoice(context, 'voice', room.voice)),
        RoomFact(
          t('eligibility'),
          roomChoice(context, 'eligibility', room.eligibility),
        ),
        RoomFact(
          t('password'),
          t(room.passwordRequired ? 'required' : 'notRequired'),
        ),
      ],
    );
  }
}
