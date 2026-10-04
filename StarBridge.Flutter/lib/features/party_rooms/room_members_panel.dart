import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/shell/chrome/presence_color.dart';
import '../common/social_identity_text.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'party_rooms_module.dart';
import 'room_action_dialogs.dart';
import 'room_display.dart';
import 'room_member_menu.dart';
import 'room_member_policy.dart';

class RoomMembersPanel extends StatefulWidget {
  const RoomMembersPanel({
    super.key,
    required this.room,
    required this.serverTime,
    this.onRemove,
    this.onTransfer,
    this.memberBuilder,
    this.listKey,
    this.showRoomCode = true,
  });
  final PartyRoom room;
  final DateTime serverTime;
  final void Function(RoomMember)? onRemove;
  final void Function(RoomMember)? onTransfer;

  /// A transport-specific renderer may supply an already-authorized row without
  /// giving this presentation widget command tokens or account references.
  final Widget Function(BuildContext, int, RoomMember)? memberBuilder;
  final Key? listKey;
  final bool showRoomCode;
  @override
  State<RoomMembersPanel> createState() => _RoomMembersPanelState();
}

class _RoomMembersPanelState extends State<RoomMembersPanel> {
  bool _details = false;
  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    String t(String key) => roomText(context, key);
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  room.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _details = !_details),
                child: Text(t(_details ? 'hideDetails' : 'roomDetails')),
              ),
            ],
          ),
          if (widget.showRoomCode && room.roomCode.isNotEmpty)
            Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectableText(
                  '${roomActionText(context, 'code')}：${room.roomCode}',
                ),
                TextButton(
                  onPressed: () {
                    if (!mounted || !widget.showRoomCode) return;
                    Clipboard.setData(
                      ClipboardData(text: widget.room.roomCode),
                    );
                  },
                  child: Text(roomActionText(context, 'copyCode')),
                ),
              ],
            ),
          if (room.goal.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(room.goal, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if (room.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            RoomTags(room: room),
          ],
          if (_details)
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(room.goal.isEmpty ? t('noGoal') : room.goal),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 18,
                        runSpacing: 10,
                        children: [
                          for (final entry in {
                            'admission': room.admissionMode,
                            'eligibility': room.eligibility,
                            'voice': room.voice,
                            'language': room.language,
                          }.entries)
                            RoomFact(
                              t(entry.key),
                              roomChoice(context, entry.key, entry.value),
                            ),
                          RoomFact(
                            t('visibility'),
                            t(room.isPublic ? 'public' : 'unlisted'),
                          ),
                          RoomFact(
                            t('password'),
                            t(
                              room.passwordRequired
                                  ? 'required'
                                  : 'notRequired',
                            ),
                          ),
                          RoomFact(
                            t('recruitment'),
                            t(
                              room.recruitmentClosesAt?.isBefore(
                                        widget.serverTime,
                                      ) ==
                                      true
                                  ? 'closed'
                                  : 'open',
                            ),
                          ),
                          RoomFact(
                            t('expires'),
                            roomDate(context, room.expiresAt),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Divider(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('members'),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${room.members.length} / ${room.capacity}',
                style: TextStyle(color: context.tokens.colors.accent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              key: widget.listKey ?? ValueKey('room-details-${room.id}'),
              itemCount: room.members.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  widget.memberBuilder?.call(
                    context,
                    index,
                    room.members[index],
                  ) ??
                  RoomMemberBanner(
                    member: room.members[index],
                    trailing:
                        canRemoveRoomMember(room, room.members[index]) &&
                            (widget.onRemove != null ||
                                widget.onTransfer != null)
                        ? RoomMemberMenu(
                            onRemove: widget.onRemove == null
                                ? null
                                : () => widget.onRemove!(room.members[index]),
                            onTransfer: widget.onTransfer == null
                                ? null
                                : () => widget.onTransfer!(room.members[index]),
                          )
                        : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class RoomMemberBanner extends StatelessWidget {
  const RoomMemberBanner({
    super.key,
    required this.member,
    this.portrait,
    this.trailing,
  });
  final RoomMember member;
  final Widget? portrait;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    String t(String key) => roomText(context, key);
    final colors = context.tokens.colors;
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        portrait ?? RoomAvatar(member: member, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SocialIdentityText(
                callsign: member.callsign.isEmpty && member.gameId.isEmpty
                    ? t('unnamedMember')
                    : member.callsign,
                gameId: member.gameId,
                callsignStyle: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                gameIdColor: colors.textSecondary,
                maxLines: 2,
              ),
              if (member.isHost)
                Text(
                  t('host'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.accent),
                ),
              const SizedBox(height: 4),
              Text(
                member.presence.isEmpty ? t('notShared') : member.presence,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: presenceColor(
                    context.tokens.colors,
                    member.presenceKey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final facts = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: RoomFact(
            t('server'),
            roomServerRegion(context, member.serverRegion),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: RoomFact(t('ship'), roomShip(context, member)),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: RoomFact(t('location'), roomLocation(context, member)),
        ),
      ],
    );
    return Container(
      key: ValueKey('member-banner-${member.gameId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.accentSoft.withValues(alpha: .25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.textSecondary.withValues(alpha: .2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 640
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 205, child: identity),
                  const SizedBox(width: 16),
                  Expanded(child: facts),
                  const SizedBox(width: 8),
                  SizedBox(width: 40, child: trailing),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      ?trailing,
                    ],
                  ),
                  const SizedBox(height: 12),
                  facts,
                ],
              ),
      ),
    );
  }
}
