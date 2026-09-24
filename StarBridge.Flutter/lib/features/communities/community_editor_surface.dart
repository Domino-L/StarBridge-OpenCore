import 'package:flutter/material.dart';

/// The same editor can live in the settings workspace or in a standalone dialog.
/// Embedded editors must delegate leaving to the workspace's draft guard.
class CommunityEditorSurface extends StatelessWidget {
  const CommunityEditorSurface({
    required this.embedded,
    required this.child,
    this.insetPadding = const EdgeInsets.all(20),
    super.key,
  });
  final bool embedded;
  final Widget child;
  final EdgeInsets insetPadding;

  @override
  Widget build(BuildContext context) => embedded
      ? SizedBox.expand(child: child)
      : Dialog(insetPadding: insetPadding, child: child);
}

class CommunityEditorAlertSurface extends StatelessWidget {
  const CommunityEditorAlertSurface({
    required this.embedded,
    required this.title,
    required this.content,
    required this.actions,
    super.key,
  });
  final bool embedded;
  final Widget title, content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => embedded
      ? Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.titleLarge,
                child: title,
              ),
              const SizedBox(height: 16),
              Expanded(child: content),
              const Divider(height: 24),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ),
        )
      : AlertDialog(title: title, content: content, actions: actions);
}
