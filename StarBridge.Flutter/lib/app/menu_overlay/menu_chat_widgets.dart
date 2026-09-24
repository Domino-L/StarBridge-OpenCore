import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/direct_messages/chat_message_bubble.dart';
import 'menu_inline_avatar.dart';

class MenuChatHeader extends StatelessWidget {
  const MenuChatHeader({
    super.key,
    required this.title,
    this.subtitle = '',
    this.portrait,
    this.trailing,
  });
  final String title, subtitle;
  final Widget? portrait, trailing;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: context.tokens.surfaces.raised.fill,
      border: Border(
        bottom: BorderSide(color: context.tokens.surfaces.panel.border),
      ),
    ),
    child: Row(
      children: [
        if (portrait != null) ...[portrait!, const SizedBox(width: 10)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Keep the client's chat anatomy. Only a genuinely narrow reading column
/// drops portraits; names, time, content and actions remain available.
class MenuChatMessage extends StatelessWidget {
  const MenuChatMessage({
    super.key,
    required this.incoming,
    required this.sender,
    required this.time,
    required this.child,
    this.portrait,
  });
  final bool incoming;
  final String sender, time;
  final Widget child;
  final Widget? portrait;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ChatMessageBubble(
      incoming: incoming,
      sender: sender,
      time: time,
      compact:
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
          380,
      avatarWidget: portrait ?? MenuInlineAvatar(name: sender),
      child: child,
    ),
  );
}

/// Same trailing send placement as the in-app composers, at every width.
class MenuChatSendBar extends StatelessWidget {
  const MenuChatSendBar({
    super.key,
    required this.length,
    required this.sendKey,
    required this.onSend,
    this.leading,
  });
  final int length;
  final Key sendKey;
  final VoidCallback? onSend;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ?leading,
              Text(
                '$length/1000',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Enter 发送 · Shift+Enter 换行',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          key: sendKey,
          onPressed: onSend,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
          child: const Text('发送'),
        ),
      ],
    ),
  );
}
