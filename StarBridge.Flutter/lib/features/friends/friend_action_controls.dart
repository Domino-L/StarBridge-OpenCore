import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'friends_module.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

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
            StarBridgeActionButton(
              controlKey: ValueKey('friend-$action-${row.targetRef}'),
              onActivate: module.canExecute(row, action)
                  ? (_) => perform(context, action)
                  : null,
              nativeStyle: OutlinedButton.styleFrom(
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

  Future<void> perform(BuildContext context, String action) =>
      runStarBridgeActivation<void>(
        StarBridgeActivationOrigin.sourceOf(context),
        () => _perform(context, action),
      );

  Future<void> _perform(BuildContext context, String action) async {
    if (action == 'remove' || action == 'block') {
      final revision = module.accountRevision;
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = StarBridgeDialogRoute<bool>(
        data:
            InteractionScope.maybeOf(context) ??
            resolveStarBridgeInteraction(context),
        link: InteractionScope.linkOf(context),
        instant:
            currentStarBridgeActivationSource == InteractionSource.keyboard,
        barrierLabel: MaterialLocalizations.of(context)
            .modalBarrierDismissLabel,
        builder: (dialogContext) {
          final live = InteractionScope.of(dialogContext);
          return StarBridgeInteractionConfiguration(
            suite: live.suite,
            reduceMotion: live.reduceMotion,
            child: ListenableBuilder(
              listenable: module,
              builder: (_, _) => AlertDialog(
                title: Text(t(dialogContext, 'action.$action')),
                content: Text(
                  '${row.name}\n\n${t(dialogContext, 'confirm.$action')}',
                ),
                actions: [
                  StarBridgeActionButton(
                    controlKey: const Key('friend-confirm-keep'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: (source) => dismissStarBridgeDialog(
                      dialogContext,
                      source: source,
                      result: false,
                    ),
                    child: Text(t(dialogContext, 'keep.$action')),
                  ),
                  StarBridgeActionButton(
                    controlKey: const Key('friend-confirm-apply'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate:
                        revision == module.accountRevision &&
                            module.canExecute(row, action)
                        ? (source) => dismissStarBridgeDialog(
                            dialogContext,
                            source: source,
                            result: true,
                          )
                        : null,
                    nativeStyle: TextButton.styleFrom(
                      foregroundColor: dialogContext.tokens.colors.danger,
                    ),
                    child: Text(t(dialogContext, 'action.$action')),
                  ),
                ],
              ),
            ),
          );
        },
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
