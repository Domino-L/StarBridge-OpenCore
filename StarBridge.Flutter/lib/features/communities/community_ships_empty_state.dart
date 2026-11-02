import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_ships_copy.dart';

/// A centred message with at most one way out: clear the filters, or retry.
class CommunityShipsEmptyState extends StatelessWidget {
  const CommunityShipsEmptyState({
    required this.message,
    this.onClear,
    this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback? onClear, onRetry;

  @override
  Widget build(BuildContext context) {
    String t(String key) => communityShipsText(context, key);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            if (onClear != null)
              StarBridgeActionButton(
                controlKey: const Key('community-ships-clear'),
                kind: StarBridgeActionKind.quiet,
                onActivate: (_) => onClear!(),
                child: Text(t('clear')),
              )
            else if (onRetry != null)
              StarBridgeActionButton(
                controlKey: const Key('community-ships-retry'),
                kind: StarBridgeActionKind.quiet,
                onActivate: (_) => onRetry!(),
                child: Text(t('refresh')),
              ),
          ],
        ),
      ),
    );
  }
}

/// "已显示 x / y" with the load-more action while the server has more.
class CommunityShipsLoadMoreRow extends StatelessWidget {
  const CommunityShipsLoadMoreRow({
    required this.shown,
    required this.total,
    required this.hasMore,
    required this.onMore,
    super.key,
  });

  final int shown, total;
  final bool hasMore;

  /// Null while a read is busy.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    String t(String key) => communityShipsText(context, key);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Text(
            t('shown')
                .replaceAll('{shown}', '$shown')
                .replaceAll('{total}', '$total'),
            style: TextStyle(color: context.tokens.colors.textSecondary),
          ),
          const Spacer(),
          if (hasMore)
            StarBridgeActionButton(
              controlKey: const Key('community-ships-next'),
              kind: StarBridgeActionKind.quiet,
              onActivate: onMore == null ? null : (_) => onMore!(),
              child: Text(t('more')),
            ),
        ],
      ),
    );
  }
}
