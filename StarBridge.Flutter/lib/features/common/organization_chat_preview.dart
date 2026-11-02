import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../communities/community_author_projection.dart';
import '../communities/community_chat_copy.dart';
import '../communities/community_chat_port.dart';
import '../communities/community_workspace_copy.dart';

/// The upper screen's chat tile (organizations and the main fleet): the newest
/// messages that fit [height], at least one, one line each; two lines per
/// message when the room allows. Only what the page already read.
class OrganizationChatPreview extends StatelessWidget {
  const OrganizationChatPreview({
    required this.messages,
    required this.unread,
    required this.height,
    super.key,
  });

  final List<CommunityChatMessage> messages;
  final int unread;
  final double height;

  static const _gap = 6.0;

  /// How many of [total] messages fit [height], at least one.
  static int fitCount(BuildContext context, double height, int total) {
    final line = _lineHeight(context);
    return ((height + _gap) / (line + _gap)).floor().clamp(
      1,
      math.max(1, total),
    );
  }

  static double _lineHeight(BuildContext context) =>
      (TextPainter(
        text: TextSpan(
          text: '测Ag',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout()).height.ceilToDouble();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final small = Theme.of(context).textTheme.bodySmall;
    final line = _lineHeight(context);
    TextStyle? style(bool primary) => small?.copyWith(
      color: primary ? tokens.colors.textPrimary : tokens.colors.textDisabled,
    );
    if (messages.isEmpty) {
      return Text(
        workspaceText(context, 'holo.noMessages'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style(false),
      );
    }
    final fit = fitCount(context, height, messages.length);
    final shown = messages.sublist(messages.length - fit);
    final lines = (height + _gap) / fit - _gap >= line * 2 ? 2 : 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, message) in shown.indexed) ...[
          if (index > 0) const SizedBox(height: _gap),
          Text.rich(
            _line(context, message, tokens.colors.textSecondary),
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            style: style(index >= shown.length - unread),
          ),
        ],
      ],
    );
  }

  TextSpan _line(
    BuildContext context,
    CommunityChatMessage message,
    Color authorColor,
  ) {
    final author = message.callsign.isNotEmpty
        ? message.callsign
        : message.isSelf
        ? communityChatText(context, 'self')
        : message.authorIdentity?.state == CommunityAuthorState.hidden
        ? communityChatText(context, 'member')
        : '';
    final body = message.text.trim().isEmpty && message.hasAttachment
        ? workspaceText(context, 'holo.attachment')
        : message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return TextSpan(
      children: [
        if (author.isNotEmpty)
          TextSpan(
            text: '$author：',
            style: TextStyle(color: authorColor),
          ),
        TextSpan(text: body),
      ],
    );
  }
}
