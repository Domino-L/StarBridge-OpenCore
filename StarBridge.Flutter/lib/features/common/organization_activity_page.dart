import 'package:flutter/material.dart';

/// The lower screen's "活动" page, for the main fleet and communities: where
/// members learn what is new. Each side lists only what it really has.
class OrganizationActivityPage extends StatelessWidget {
  const OrganizationActivityPage({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('organization-activity-page'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 16),
      for (final (index, child) in children.indexed) ...[
        if (index > 0) const SizedBox(height: 16),
        child,
      ],
    ],
  );
}
