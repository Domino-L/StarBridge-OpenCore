import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../direct_messages/chat_send_shortcuts.dart';
import 'room_action_dialogs.dart';

/// Room editor presentation shared by client and menu. No transport or timers.
class RoomChatComposer extends StatelessWidget {
  const RoomChatComposer({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSend,
    this.enabled = true,
    this.readOnly = false,
    this.sending = false,
    this.leadingAction,
    this.attachment,
    this.inputKey,
    this.sendKey,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSend;
  final bool enabled, readOnly, sending;
  final Widget? leadingAction, attachment;
  final Key? inputKey, sendKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      ?attachment,
      ChatSendShortcuts(
        controller: controller,
        onSend: onSend,
        child: TextField(
          key: inputKey,
          controller: controller,
          maxLength: 300,
          minLines: 1,
          maxLines: 3,
          enabled: enabled,
          readOnly: readOnly,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: roomActionText(context, 'chatDraft'),
            helperText: AppStrings.of(context).text('direct.send.shortcut'),
          ),
        ),
      ),
      Row(
        children: [
          ?leadingAction,
          const Spacer(),
          FilledButton(
            key: sendKey,
            onPressed: onSend,
            child: Text(roomActionText(context, sending ? 'working' : 'send')),
          ),
        ],
      ),
    ],
  );
}
