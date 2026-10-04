import 'package:flutter/material.dart';

import '../direct_messages/chat_send_shortcuts.dart';
import 'community_chat_copy.dart';

/// Shared presentation only; sending and permission checks remain with callers.
class CommunityChatComposer extends StatelessWidget {
  const CommunityChatComposer({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSend,
    required this.enabled,
    this.readOnly = false,
    this.canSend = true,
    this.inputKey,
    this.sendKey,
    this.maxLength = 1000,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSend;
  final bool enabled, readOnly, canSend;
  final Key? inputKey, sendKey;
  final int maxLength;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChatSendShortcuts(
        controller: controller,
        onSend: onSend,
        child: TextField(
          key: inputKey,
          controller: controller,
          enabled: enabled,
          readOnly: readOnly,
          minLines: 1,
          maxLines: 4,
          maxLength: maxLength,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: communityChatText(context, 'draft'),
          ),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              communityChatText(context, 'keys'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          FilledButton(
            key: sendKey,
            onPressed: canSend ? onSend : null,
            child: Text(communityChatText(context, 'send')),
          ),
        ],
      ),
    ],
  );
}
