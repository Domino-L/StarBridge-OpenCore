import '../../features/direct_messages/direct_messages_module.dart';
import '../../features/common/chat_room_invitation.dart';
import '../../features/communities/community_invitation_attachment.dart';
import '../../features/notifications/notification_inbox_controller.dart';

Map<String, Object?> encodeConversation(Conversation c) => {
  'ref': c.ref,
  'name': c.name,
  'preview': c.preview,
  'time': c.time.toIso8601String(),
  'unread': c.unread,
  'state': c.state,
  'avatar': c.avatar,
  'key': c.conversationKey,
  'gameId': c.gameId,
  'presence': conversationPresence(c.state, c.presence),
};
Conversation decodeConversation(Map c) => Conversation(
  c['ref'] as String,
  c['name'] as String,
  c['preview'] as String,
  DateTime.parse(c['time'] as String),
  c['unread'] as int,
  c['state'] as String,
  avatar: c['avatar'] as String?,
  conversationKey: c['key'] as String?,
  gameId: c['gameId'] as String? ?? '',
  presence: conversationPresence(c['state'] as String, c['presence']),
);
Map<String, Object?> encodeMessage(DirectMessage m) => {
  'sequence': m.sequence,
  'id': m.id,
  'incoming': m.incoming,
  'text': m.text,
  'time': m.time.toIso8601String(),
  'attachment': m.attachment,
  if (m.roomInvitation case final room?) 'roomInvite': room.toJson(),
  if (m.communityInvitation case final invite?)
    'invite': {
      'title': invite.title,
      'summary': invite.summary,
      'inviteCode': invite.inviteCode,
      'expiresAt': invite.expiresAt?.toIso8601String(),
    },
};
DirectMessage decodeMessage(Map m) => DirectMessage(
  m['sequence'] as int,
  m['id'] as String,
  m['incoming'] as bool,
  m['text'] as String,
  DateTime.parse(m['time'] as String),
  m['attachment'] as String?,
  communityInvitation: m['invite'] is Map
      ? CommunityInvitationAttachment.parse(m['invite'] as Map)
      : null,
  roomInvitation: m['roomInvite'] is Map
      ? ChatRoomInvitation.parse(m['roomInvite'] as Map)
      : null,
);
Map<String, Object?> encodeInbox(InboxItem i) => {
  'reference': i.reference,
  'category': i.category,
  'priority': i.priority,
  'title': i.title,
  'body': i.body,
  'createdAt': i.created.toIso8601String(),
  'read': i.read,
  'actionTarget': i.target,
  'actionLabel': i.action,
  'isAvailable': i.available,
};
