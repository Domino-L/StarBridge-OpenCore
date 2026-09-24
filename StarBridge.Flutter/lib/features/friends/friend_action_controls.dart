import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'friends_module.dart';

class FriendActionControls extends StatelessWidget {
  const FriendActionControls({
    required this.module,
    required this.row,
    this.compact = false,
    super.key,
  });
  final FriendsModule module;
  final FriendRow row;
  final bool compact;
  String t(BuildContext context, String key) =>
      AppStrings.of(context).text('friends.$key');
  @override
  Widget build(BuildContext context) {
    if (!module.commandsAvailable || row.actions.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.tokens.colors;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 0 : 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in row.actions)
            OutlinedButton(
              key: ValueKey('friend-$action-${row.targetRef}'),
              onPressed: module.canExecute(row, action)
                  ? () => perform(context, action)
                  : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: switch (action) {
                  'remove' || 'block' => colors.danger,
                  'accept' => colors.success,
                  'send' || 'unblock' => colors.accent,
                  _ => colors.textSecondary,
                },
              ),
              child: Text(t(context, 'action.$action')),
            ),
        ],
      ),
    );
  }

  Future<void> perform(BuildContext context, String action) async {
    if (action == 'remove' || action == 'block') {
      final revision = module.accountRevision;
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<bool>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: module,
          builder: (_, _) => AlertDialog(
            title: Text(t(dialogContext, 'action.$action')),
            content: Text(
              '${row.name}\n\n${t(dialogContext, 'confirm.$action')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(t(dialogContext, 'keep.$action')),
              ),
              TextButton(
                onPressed:
                    revision == module.accountRevision &&
                        module.canExecute(row, action)
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                style: TextButton.styleFrom(
                  foregroundColor: dialogContext.tokens.colors.danger,
                ),
                child: Text(t(dialogContext, 'action.$action')),
              ),
            ],
          ),
        ),
      );
      void invalidate() {
        if (revision != module.accountRevision && route.isActive) {
          navigator.removeRoute(route);
        }
      }

      module.addListener(invalidate);
      bool? approved;
      try {
        approved = await navigator.push(route);
      } finally {
        module.removeListener(invalidate);
      }
      if (approved != true ||
          !context.mounted ||
          revision != module.accountRevision) {
        return;
      }
    }
    await module.execute(row, action);
  }
}
