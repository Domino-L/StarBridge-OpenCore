import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../common/user_interaction.dart';
import 'chat_message_bubble.dart';
import 'direct_message_outgoing_bubble.dart';
import 'direct_messages_module.dart';

/// Newest first: the user's own messages not yet in history (A2), then the
/// confirmed history, then the "older" control.
class DirectMessageHistoryList extends StatelessWidget {
  const DirectMessageHistoryList({
    required this.module,
    required this.target,
    required this.scroll,
    required this.messageKeys,
    required this.time,
    required this.body,
    this.openProfile,
    super.key,
  });
  final DirectMessagesModule module;
  final Conversation target;
  final ScrollController scroll;
  final Map<String, GlobalKey> messageKeys;
  final String Function(DateTime) time;
  final Widget Function(DirectMessage) body;
  final VoidCallback? openProfile;

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.of(context).text('direct.$key');
    final outgoing = module.outgoing;
    if (module.messages.isEmpty && outgoing.isEmpty && !module.hasOlder) {
      return Center(
        child: Text(
          t(
            module.busy
                ? 'loading'
                : module.error != null || module.historySyncError != null
                ? 'refreshHint'
                : 'emptyHistory',
          ),
        ),
      );
    }
    final userTarget = UserTarget(
      'conversation',
      target.ref,
      query: target.gameId,
    );
    return ListView.builder(
      key: ValueKey(target.ref),
      controller: scroll,
      reverse: true,
      itemCount: outgoing.length + module.messages.length + 1,
      itemBuilder: (context, index) {
        if (index < outgoing.length) {
          final message = outgoing[outgoing.length - 1 - index];
          return DirectOutgoingBubble(
            key: ValueKey('outgoing-${message.id}'),
            message: message,
            time: time(message.time),
            avatar: module.viewerAvatar,
            userTarget: userTarget,
            onRetry: () => module.retrySend(message.id),
          );
        }
        final position = index - outgoing.length;
        if (position == module.messages.length) {
          return Center(
            child: module.hasOlder
                ? StarBridgeActionButton(
                    controlKey: const ValueKey('chat-older'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: module.busy
                        ? null
                        : (_) => module.load(older: true),
                    child: Text(t('older')),
                  )
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(t('start')),
                  ),
          );
        }
        final message = module.messages[module.messages.length - 1 - position];
        return KeyedSubtree(
          key: messageKeys.putIfAbsent(message.id, GlobalKey.new),
          child: ChatMessageBubble(
            privateConversation: true,
            onViewProfile: message.incoming ? openProfile : null,
            userTarget: userTarget,
            key: ValueKey(message.id),
            incoming: message.incoming,
            sender: message.incoming ? target.name : t('me'),
            time: time(message.time),
            avatar: message.incoming ? target.avatar : module.viewerAvatar,
            allowProfileUrl: !message.incoming,
            child: body(message),
          ),
        );
      },
    );
  }
}
