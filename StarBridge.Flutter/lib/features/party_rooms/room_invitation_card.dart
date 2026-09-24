import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'party_rooms_module.dart';
import 'room_display.dart';
import 'room_directory_card.dart';
import 'room_invitations.dart';

class RoomInvitationCard extends StatelessWidget {
  const RoomInvitationCard({
    required this.invitation,
    required this.room,
    required this.actions,
    this.sent = false,
    this.loading = false,
    super.key,
  });
  final RoomInvitation invitation;
  final PartyRoom? room;
  final Widget actions;
  final bool sent, loading;
  @override
  Widget build(BuildContext context) {
    final details = room;
    return Card.outlined(
      key: ValueKey('invitation-card-${invitation.id}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    details?.title ?? invitation.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (details != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${details.members.length} / ${details.capacity}',
                    style: TextStyle(
                      color: details.members.length >= details.capacity
                          ? context.tokens.colors.warning
                          : context.tokens.colors.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${roomText(context, sent ? 'inviteRecipient' : 'inviteSender')}：${sent ? invitation.recipient : invitation.inviter}',
            ),
            if (details != null) ...[
              if (details.goal.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  details.goal,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              RoomJoinFacts(room: details),
              if (details.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                RoomTags(room: details),
              ],
            ] else ...[
              const SizedBox(height: 12),
              if (loading)
                const LinearProgressIndicator()
              else
                Text(roomText(context, 'invitationDetailsUnavailable')),
            ],
            const Divider(height: 24),
            Text(
              '${roomText(context, 'invitationExpires')}：${roomDate(context, invitation.expiresAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Align(alignment: AlignmentDirectional.centerEnd, child: actions),
          ],
        ),
      ),
    );
  }
}
