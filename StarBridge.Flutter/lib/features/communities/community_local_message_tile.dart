import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../app/localization/app_strings.dart';
import '../direct_messages/chat_message_bubble.dart';
import '../direct_messages/communication_time_formatter.dart';
import 'community_chat_controller.dart';
import 'community_chat_copy.dart';

/// No synthetic message references, avatar lookups, profile links or receipts.
class CommunityLocalMessageTile extends StatelessWidget {
  const CommunityLocalMessageTile({
    required CommunityLocalMessage message,
    this.avatar,
    this.onRetry,
    this.onCheck,
    this.onRestore,
    this.composerOccupied = false,
    super.key,
    // Preserve the non-null domain constructor alongside the display-only one.
    // ignore: prefer_initializing_formals
  }) : _message = message,
       text = '',
       state = '',
       error = null,
       createdAt = null;

  /// A menu receives display data only, never synthetic domain request IDs.
  const CommunityLocalMessageTile.presentation({
    required this.text,
    required this.state,
    required this.createdAt,
    this.error,
    this.avatar,
    this.onRetry,
    this.onCheck,
    this.onRestore,
    this.composerOccupied = false,
    super.key,
  }) : _message = null;
  final CommunityLocalMessage? _message;
  final String text, state;
  final String? error;
  final DateTime? createdAt;
  final String? avatar;
  final VoidCallback? onRetry, onCheck, onRestore;
  final bool composerOccupied;

  @override
  Widget build(BuildContext context) {
    final message = _message;
    final state = message?.state ?? this.state;
    final text = message?.intent.text ?? this.text;
    final error = message?.error ?? this.error;
    String t(String key) => communityChatText(context, key);
    final status = switch (state) {
      'sending' => 'localSending',
      'sent' => 'localSent',
      'unknown' => 'localUnknown',
      _ => error == 'rateLimited' ? 'localRateLimited' : 'localFailed',
    };
    final warning = state == 'failed' || state == 'unknown';
    final statusColor = warning
        ? context.tokens.colors.warning
        : Theme.of(context).textTheme.bodySmall?.color;
    return ChatMessageBubble(
      incoming: false,
      sender: t('self'),
      avatar: avatar,
      time: communicationTime(
        message?.createdAt ?? createdAt!,
        AppStrings.of(context).locale,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text.isNotEmpty) SelectableText(text),
          if (message?.intent.attachment case final attachment?)
            Text('${t('preset')} · ${attachment['title'] ?? ''}'),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: warning,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: state == 'sending'
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : StandardIcon(
                          warning
                              ? StandardIconSemantic.warningAmber
                              : StandardIconSemantic.checkCircle,
                          size: 14,
                          color: statusColor,
                        ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    t(status),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: statusColor),
                  ),
                ),
              ],
            ),
          ),
          if (warning) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  onPressed: state == 'failed' ? onRetry : onCheck,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.tokens.colors.warning,
                    side: BorderSide(color: context.tokens.colors.warning),
                    minimumSize: const Size(64, 44),
                  ),
                  child: Text(t(state == 'failed' ? 'retry' : 'checkSend')),
                ),
                if (state == 'failed')
                  TextButton(
                    onPressed: onRestore,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 44),
                    ),
                    child: Text(t('restoreLocalDraft')),
                  ),
              ],
            ),
            if (state == 'failed' && composerOccupied)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t('restoreLocalBlocked'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
