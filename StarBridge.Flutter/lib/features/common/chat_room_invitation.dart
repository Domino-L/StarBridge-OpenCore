import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/routing/open_destination_intent.dart';
import '../../app/routing/room_invitation_destination.dart';

class ChatRoomInvitation {
  const ChatRoomInvitation(
    this.title,
    this.summary,
    this.invitationId,
    this.expiresAt,
  );
  final String title, summary, invitationId;
  final DateTime expiresAt;
  Map<String, Object?> toJson() => {
    'title': title,
    'summary': summary,
    'invitationId': invitationId,
    'expiresAt': expiresAt.toIso8601String(),
  };
  factory ChatRoomInvitation.parse(Map value) {
    String text(String key, int limit) {
      final item = value[key];
      if (item is! String ||
          item.trim().isEmpty ||
          item.length > limit ||
          item.runes.any((x) => x < 32 || x == 127)) {
        throw const FormatException('Invalid invitation');
      }
      return item;
    }

    final id = text('invitationId', 80);
    if (!validRoomInvitationId(id)) {
      throw const FormatException('Invalid invitation');
    }
    return ChatRoomInvitation(
      text('title', 64),
      text('summary', 240),
      id,
      DateTime.parse(text('expiresAt', 64)),
    );
  }
}

class ChatRoomInvitationCard extends StatelessWidget {
  const ChatRoomInvitationCard({required this.value, super.key});
  final ChatRoomInvitation value;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final intent = OpenDestinationIntent(
      '/rooms/invitations?invitation=${Uri.encodeQueryComponent(value.invitationId)}',
    );
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.text('direct.attachment.party_room_invitation')),
            const SizedBox(height: 8),
            Text(value.title, style: Theme.of(context).textTheme.titleSmall),
            Text(value.summary),
            if (!value.expiresAt.isAfter(DateTime.now()))
              Text(roomInvitationText(context, 'expired')),
            OutlinedButton(
              onPressed:
                  Actions.maybeFind<OpenDestinationIntent>(context) == null
                  ? null
                  : () => Actions.invoke(context, intent),
              child: Text(strings.text('direct.viewInvite')),
            ),
          ],
        ),
      ),
    );
  }
}

String roomInvitationText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final index = locale.languageCode != 'zh'
      ? 2
      : locale.countryCode == 'TW'
      ? 1
      : 0;
  return (switch (key) {
    'expired' => ['邀请已过期。', '邀請已過期。', 'This invitation has expired.'],
    'unavailable' => [
      '邀请已失效或已处理，请向房主确认。',
      '邀請已失效或已處理，請向房主確認。',
      'This invitation is no longer available or has been handled. Check with the host.',
    ],
    'alreadyJoined' => [
      '你已在此房间中。',
      '你已在此房間中。',
      'You are already in this room.',
    ],
    'inAnotherRoom' => [
      '你已加入其他房间，退出后才能接受邀请。',
      '你已加入其他房間，退出後才能接受邀請。',
      'Leave your current room before accepting this invitation.',
    ],
    _ => throw ArgumentError.value(key),
  })[index];
}
