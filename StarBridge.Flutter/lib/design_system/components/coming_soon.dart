import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../tokens/starbridge_tokens.dart';

/// Neutral availability label, not an error or a live connection state.
class ComingSoonBadge extends StatelessWidget {
  const ComingSoonBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: context.tokens.surfaces.raised.fill,
      borderRadius: context.tokens.shape.small,
    ),
    child: Text(
      AppStrings.of(context).text('deferredFeature.title'),
      maxLines: 1,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: context.tokens.colors.textSecondary),
    ),
  );
}

/// Intentionally has no action/control slots for unavailable capabilities.
class ComingSoonSection extends StatelessWidget {
  const ComingSoonSection({super.key, required this.title, this.description});
  final String title;
  final String? description;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [Text(title), const ComingSoonBadge()],
      ),
      const SizedBox(height: 8),
      Text(
        description ??
            AppStrings.of(context)
                .text('comingSoon.section')
                .replaceAll('{feature}', title),
      ),
    ],
  );
}
