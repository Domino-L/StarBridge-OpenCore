import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/user_interaction.dart';
import 'chat_message_bubble.dart';
import 'direct_message_send_queue.dart';

/// A2 (2026-10-21 user choice): an own message before history returns it.
/// The bubble is the normal outgoing bubble; only the time slot changes: a
/// small clock while sending, "发送失败 · 重试" plus a danger alert beside the
/// bubble when it failed. The text stays until it is sent or retried.
class DirectOutgoingBubble extends StatelessWidget {
  const DirectOutgoingBubble({
    required this.message,
    required this.time,
    required this.onRetry,
    this.avatar,
    this.userTarget,
    super.key,
  });
  final DirectOutgoing message;
  final String time;
  final VoidCallback onRetry;
  final String? avatar;
  final UserTarget? userTarget;

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.of(context).text('direct.$key');
    final colors = context.tokens.colors;
    final small = Theme.of(context).textTheme.bodySmall;
    final Widget? timeLabel = switch (message.state) {
      DirectOutgoingState.sending => Semantics(
        key: ValueKey('chat-send-pending-${message.id}'),
        label: t('send.pendingTip'),
        child: StandardIcon(
          StandardIconSemantic.schedule,
          size: 12,
          color: colors.textSecondary,
        ),
      ),
      DirectOutgoingState.failed => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t('send.failed'), style: small?.copyWith(color: colors.danger)),
          Text(' · ', style: small),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: ValueKey('chat-send-retry-${message.id}'),
              onTap: onRetry,
              child: Text(
                t('send.retry'),
                style: small?.copyWith(
                  color: colors.accent,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
      DirectOutgoingState.confirmed => null,
    };
    return ChatMessageBubble(
      privateConversation: true,
      incoming: false,
      sender: t('me'),
      time: time,
      avatar: avatar,
      allowProfileUrl: true,
      userTarget: userTarget,
      timeLabel: timeLabel,
      sideAlert: message.state == DirectOutgoingState.failed
          ? StarBridgeIconAction(
              controlKey: ValueKey('chat-send-alert-${message.id}'),
              label: t('send.failedTip'),
              constraints: const BoxConstraints.tightFor(width: 20, height: 20),
              padding: EdgeInsets.zero,
              onActivate: (_) => onRetry(),
              icon: StandardIcon(
                StandardIconSemantic.warningAmber,
                size: 16,
                color: colors.danger,
              ),
            )
          : null,
      child: SelectableText(message.text),
    );
  }
}
