import 'package:flutter/material.dart';

import '../../../design_system/styles/attention_badge_palette.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';

/// Place inside a button's content, never around its hit target.
class AttentionBadge extends StatelessWidget {
  const AttentionBadge({required this.count, required this.child, super.key});
  final int count;
  final Widget child;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      if (count > 0) ...[
        SizedBox(width: context.tokens.space.xs),
        AttentionCount(count: count),
      ],
    ],
  );
}

class AttentionCount extends StatelessWidget {
  const AttentionCount({required this.count, super.key});
  final int count;
  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final tokens = context.tokens;
    return Semantics(
      label: '$count',
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(
          minWidth: tokens.icons.small,
          minHeight: tokens.icons.small,
        ),
        padding: EdgeInsets.symmetric(horizontal: tokens.space.xxs),
        decoration: BoxDecoration(
          color: AttentionBadgePalette.background,
          borderRadius: tokens.shape.pill,
          border: Border.all(
            color: tokens.surfaces.chrome.fill,
            width: tokens.stroke.hairline,
          ),
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            count > 99 ? '99+' : '$count',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AttentionBadgePalette.foreground,
              fontSize: tokens.typography.label - tokens.space.xxs,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
