export 'community_chat_receipt_renewal.dart';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_chat_copy.dart';

/// Asks before leaving a chat with an unsent draft. True means leave.
Future<bool?> showCommunityChatLeaveDialog(
  BuildContext context, {
  required InteractionSource source,
  required void Function(StarBridgeDialogRoute<bool>) onRouteCreated,
}) => showStarBridgeDialog<bool>(
  context,
  source: source,
  barrierDismissible: false,
  onRouteCreated: onRouteCreated,
  builder: (context) => AlertDialog(
    title: Text(communityChatText(context, 'leaveTitle')),
    content: Text(communityChatText(context, 'leaveBody')),
    actions: [
      StarBridgeActionButton(
        kind: StarBridgeActionKind.quiet,
        onActivate: (source) =>
            dismissStarBridgeDialog(context, source: source, result: false),
        child: Text(communityChatText(context, 'stay')),
      ),
      StarBridgeActionButton(
        kind: StarBridgeActionKind.danger,
        onActivate: (source) =>
            dismissStarBridgeDialog(context, source: source, result: true),
        child: Text(communityChatText(context, 'leave')),
      ),
    ],
  ),
);

/// A warning line above or below the conversation, with an optional retry.
class CommunityChatNotice extends StatelessWidget {
  const CommunityChatNotice(this.copyKey, {this.retry, super.key});

  final String copyKey;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            communityChatText(context, copyKey),
            style: TextStyle(color: context.tokens.colors.warning),
          ),
        ),
        if (retry != null)
          StarBridgeActionButton(
            controlKey: ValueKey('community-chat-notice-$copyKey'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (_) => retry!(),
            child: Text(communityChatText(context, 'retry')),
          ),
      ],
    ),
  );
}
