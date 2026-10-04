import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

class CommunityAnnouncementCard extends StatelessWidget {
  const CommunityAnnouncementCard({
    super.key,
    required this.title,
    required this.content,
    required this.metadata,
    required this.actions,
    this.maxLines,
  });
  final String title, content;
  final Widget metadata, actions;
  final int? maxLines;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.tokens.surfaces.raised.fill,
      border: Border.all(color: context.tokens.surfaces.panel.border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        metadata,
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          content,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        actions,
      ],
    ),
  );
}
