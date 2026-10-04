import '../../features/communities/community_chat_port.dart';
import '../../platform/window/menu_profile_navigation.dart';

/// Keep author renewal tied to the authenticated message, never its nickname.
/// The session owns account/list leases; renewal rechecks the account both sides
/// of the read and never sends a message or acknowledges it.
MenuProfileTarget organizationChatProfileTarget(
  CommunityChatPort port, {
  required String target,
  required CommunityChatMessage message,
  required bool Function() isCurrent,
  required bool Function() isAccountCurrent,
  String? avatar,
}) => MenuProfileTarget(
  source: message.isSelf ? 'self' : 'community',
  reference: message.isSelf ? '' : message.senderRef,
  contextRef: message.isSelf ? null : target,
  query: message.gameId,
  avatar: avatar,
  isCurrent: isCurrent,
  isAccountCurrent: isAccountCurrent,
  refreshReference: message.isSelf
      ? null
      : () async {
          if (!isAccountCurrent()) throw StateError('retired');
          final page = await port.readChat(
            target,
            before: message.sequence + 1,
          );
          if (!isAccountCurrent() || page.targetRef != target) {
            throw StateError('retired');
          }
          final author = page.messages
              .where((m) => m.sequence == message.sequence && !m.isSelf)
              .firstOrNull;
          if (author == null) throw StateError('retired');
          return author.senderRef;
        },
);
