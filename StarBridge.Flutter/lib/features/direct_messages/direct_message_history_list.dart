import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../common/user_interaction.dart';
import 'chat_message_bubble.dart';
import 'direct_message_outgoing_bubble.dart';
import 'direct_messages_module.dart';

/// Oldest first: confirmed history with the user's failed messages placed at
/// the time they were written (2026-11-19: a failed bubble must not drop below
/// later messages that did go out). Messages still sending, or confirmed but
/// not yet in history, are returned separately and stay at the bottom.
({List<Object> timeline, List<DirectOutgoing> pinned}) directMessageTimeline(
  List<DirectMessage> history,
  List<DirectOutgoing> outgoing,
) {
  final pinned = [
    for (final entry in outgoing)
      if (entry.state != DirectOutgoingState.failed) entry,
  ];
  final failed = [
    for (final entry in outgoing)
      if (entry.state == DirectOutgoingState.failed) entry,
  ];
  // Stable: equal times keep history first and failed entries in queue order.
  final order = List<int>.generate(failed.length, (i) => i)
    ..sort((a, b) {
      final byTime = failed[a].time.compareTo(failed[b].time);
      return byTime != 0 ? byTime : a.compareTo(b);
    });
  final timeline = <Object>[];
  var next = 0;
  for (final message in history) {
    while (next < order.length &&
        failed[order[next]].time.isBefore(message.time)) {
      timeline.add(failed[order[next++]]);
    }
    timeline.add(message);
  }
  while (next < order.length) {
    timeline.add(failed[order[next++]]);
  }
  return (timeline: timeline, pinned: pinned);
}

/// Newest first: the user's messages still sending (A2), then history with
/// failed messages at their own time, then the "older" control.
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
    final (:timeline, :pinned) = directMessageTimeline(
      module.messages,
      outgoing,
    );
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
      itemCount: pinned.length + timeline.length + 1,
      itemBuilder: (context, index) {
        Widget outgoingBubble(DirectOutgoing message) => DirectOutgoingBubble(
          key: ValueKey('outgoing-${message.id}'),
          message: message,
          time: time(message.time),
          avatar: module.viewerAvatar,
          userTarget: userTarget,
          onRetry: () => module.retrySend(message.id),
        );
        if (index < pinned.length) {
          return outgoingBubble(pinned[pinned.length - 1 - index]);
        }
        final position = index - pinned.length;
        if (position == timeline.length) {
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
        final item = timeline[timeline.length - 1 - position];
        if (item is DirectOutgoing) return outgoingBubble(item);
        final message = item as DirectMessage;
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
