import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo.dart';

import '../direct_messages/chat_send_shortcuts.dart';
import 'community_chat_copy.dart';
import 'community_chat_holo_typing.dart';

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
  Widget build(BuildContext context) {
    if (OrganizationHolo.of(context)) return _holo(context);
    return _standard(context);
  }

  Widget _holo(BuildContext context) {
    final tokens = context.tokens;
    final ready = canSend && onSend != null;
    final style = organizationHoloButton(context, primary: true);
    final label = Text(communityChatText(context, 'send'));
    final send = CommunityChatSendCharge(
      charged: ready,
      idle: StarBridgeActionButton(
        kind: StarBridgeActionKind.primary,
        nativeStyle: style,
        onActivate: null,
        child: label,
      ),
      child: StarBridgeActionButton(
        kind: StarBridgeActionKind.primary,
        controlKey: sendKey,
        nativeStyle: style,
        onActivate: ready ? (_) => onSend!() : null,
        child: label,
      ),
    );
    // The chamfered field and send button need the native control faces.
    return OrganizationHoloFace(child: _holoRow(context, tokens, send));
  }

  Widget _holoRow(BuildContext context, StarBridgeTokens tokens, Widget send) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: ChatSendShortcuts(
            controller: controller,
            onSend: onSend,
            child: StarBridgeFieldFrame(
              enabled: enabled,
              builder: (_, focus) => CommunityChatTypingFlow(
                controller: controller,
                child: TextField(
                  focusNode: focus,
                  key: inputKey,
                  controller: controller,
                  enabled: enabled,
                  readOnly: readOnly,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: maxLength,
                  onChanged: onChanged,
                  decoration: organizationHoloField(
                    context,
                    InputDecoration(
                      counterText: '',
                      hintText:
                          '${communityChatText(context, 'draft')} · '
                          '${communityChatText(context, 'keys')}',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: organizationHoloFieldHeight(context),
          child: Center(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => Text(
                '${value.text.characters.length}/$maxLength',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: tokens.typography.monoFamily,
                  color: tokens.colors.textDisabled,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(height: organizationHoloFieldHeight(context), child: send),
      ],
    );
  }

  Widget _standard(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChatSendShortcuts(
        controller: controller,
        onSend: onSend,
        child: StarBridgeFieldFrame(
          enabled: enabled,
          builder: (_, focus) => TextField(
            focusNode: focus,
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
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              communityChatText(context, 'keys'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: sendKey,
            onActivate: canSend && onSend != null ? (_) => onSend!() : null,
            child: Text(communityChatText(context, 'send')),
          ),
        ],
      ),
    ],
  );
}
