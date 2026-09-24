import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'chat_avatar.dart';
import '../common/user_interaction.dart';

/// Shared private/room chat structure. Routing, ownership and permissions are
/// supplied by each account-scoped module, never guessed from display names.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.incoming,
    required this.sender,
    required this.time,
    required this.child,
    this.avatar,
    this.allowProfileUrl = false,
    this.avatarWidget,
    this.userTarget,
    this.compact = false,
  });
  final bool incoming, allowProfileUrl;
  final String sender, time;
  final String? avatar;
  final Widget child;
  final Widget? avatarWidget;
  final UserTarget? userTarget;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final portrait = Padding(
      padding: EdgeInsets.only(
        top: 6,
        right: incoming ? 8 : 0,
        left: incoming ? 0 : 8,
      ),
      child:
          avatarWidget ??
          ChatAvatar(
            label: sender,
            isSelf: !incoming,
            target: userTarget,
            source: avatar,
            allowProfileUrl: allowProfileUrl,
          ),
    );
    return Align(
      alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (incoming && !compact) portrait,
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 580),
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: EdgeInsets.all(compact ? 8 : 12),
              decoration: BoxDecoration(
                color: incoming
                    ? context.tokens.surfaces.panel.fill
                    : context.tokens.surfaces.raised.fill,
                border: Border.all(color: context.tokens.surfaces.panel.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$sender · $time',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  child,
                ],
              ),
            ),
          ),
          if (!incoming && !compact) portrait,
        ],
      ),
    );
  }
}
