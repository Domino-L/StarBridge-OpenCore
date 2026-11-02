import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'chat_avatar.dart';
import '../common/organization_holo.dart';
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
    this.onViewProfile,
    this.privateConversation = false,
    this.timeLabel,
    this.sideAlert,
    this.senderExtra,
  });

  /// On organization (holo) surfaces only: shown after the sender's name,
  /// for example the role tag.
  final Widget? senderExtra;

  /// Replaces the time text (A2: a clock while sending, a failure and retry).
  final Widget? timeLabel;

  /// Shown beside an outgoing bubble (A2: the failed-send alert).
  final Widget? sideAlert;
  final bool incoming, allowProfileUrl;
  final String sender, time;
  final String? avatar;
  final Widget child;
  final Widget? avatarWidget;
  final UserTarget? userTarget;
  final bool compact;
  final VoidCallback? onViewProfile;
  final bool privateConversation;

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
            onViewProfile: onViewProfile,
            label: sender,
            isSelf: !incoming,
            target: userTarget,
            source: avatar,
            allowProfileUrl: allowProfileUrl,
          ),
    );
    // Organization work surfaces (holo, 2026-10-23): no bubble; name and
    // time over the text, your own name in accent. The general chat rule
    // still holds: others on the left, your own messages on the right.
    if (OrganizationHolo.of(context)) {
      final tokens = context.tokens;
      final text = Theme.of(context).textTheme;
      final avatarSlot = Padding(
        padding: EdgeInsets.only(
          top: 2,
          right: incoming ? 14 : 0,
          left: incoming ? 0 : 14,
        ),
        child: portrait.child,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: incoming
              ? MainAxisAlignment.start
              : MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (incoming) avatarSlot else const SizedBox(width: 96),
            Flexible(
              fit: incoming ? FlexFit.tight : FlexFit.loose,
              child: Column(
                crossAxisAlignment: incoming
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: 10,
                    alignment: incoming
                        ? WrapAlignment.start
                        : WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!incoming) ?sideAlert,
                      Text(
                        sender,
                        style: text.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: incoming ? null : tokens.colors.accent,
                        ),
                      ),
                      ?senderExtra,
                      timeLabel ??
                          Text(
                            time,
                            style: text.bodySmall?.copyWith(
                              fontFamily: tokens.typography.monoFamily,
                              color: tokens.colors.textDisabled,
                            ),
                          ),
                      if (incoming) ?sideAlert,
                    ],
                  ),
                  const SizedBox(height: 2),
                  child,
                ],
              ),
            ),
            if (!incoming) avatarSlot,
          ],
        ),
      );
    }
    return Align(
      alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (incoming && !compact) portrait,
          if (!incoming && sideAlert != null)
            Padding(
              padding: const EdgeInsets.only(top: 14, right: 6),
              child: sideAlert,
            ),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 580),
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: EdgeInsets.all(compact ? 8 : 12),
              decoration: BoxDecoration(
                color: incoming
                    ? context.tokens.surfaces.panel.fill
                    : privateConversation
                    ? Color.alphaBlend(
                        context.tokens.colors.accent.withValues(alpha: .14),
                        context.tokens.surfaces.raised.fill,
                      )
                    : context.tokens.surfaces.raised.fill,
                border: Border.all(color: context.tokens.surfaces.panel.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  timeLabel ??
                      Text(
                        privateConversation ? time : '$sender · $time',
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
