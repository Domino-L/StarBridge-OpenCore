import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'account_generation_guard.dart';
import 'account_migration.dart';
import 'account_models.dart';
import 'account_view_components.dart';

/// The one-time result after a migration finished or failed.
class AccountMigrationResult extends StatelessWidget {
  const AccountMigrationResult({
    required this.view,
    this.onRetry,
    this.onClose,
    super.key,
  });

  final AccountMigrationView view;
  final void Function(InteractionSource source)? onRetry;
  final void Function(InteractionSource source)? onClose;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final completed = view.state == AccountMigrationState.completed;
    final retryable = view.state == AccountMigrationState.failed;
    final body = Theme.of(context).textTheme.bodyMedium;
    final secondary = body?.copyWith(color: tokens.colors.textSecondary);
    String count(String key, int value) =>
        strings.text(key).replaceAll('{count}', '$value');
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: StarBridgeSurface(
          role: SurfaceRole.floating,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  StarBridgeIcon(
                    completed
                        ? StarBridgeIconSemantic.connected
                        : StarBridgeIconSemantic.warning,
                    color: completed
                        ? tokens.colors.success
                        : tokens.colors.warning,
                  ),
                  SizedBox(width: tokens.space.sm),
                  Expanded(
                    child: Text(
                      strings.text(
                        completed
                            ? 'account.migrate.resultTitle'
                            : 'account.migrate.failedTitle',
                      ),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space.md),
              if (completed) ...[
                Wrap(
                  spacing: tokens.space.lg,
                  runSpacing: tokens.space.sm,
                  children: [
                    Text(
                      count('account.migrate.resultFriends', view.friends),
                      style: body,
                    ),
                    Text(
                      count(
                        'account.migrate.resultCommunities',
                        view.communities,
                      ),
                      style: body,
                    ),
                    if (view.merged > 0)
                      Text(
                        count('account.migrate.resultMerged', view.merged),
                        style: body,
                      ),
                  ],
                ),
                SizedBox(height: tokens.space.sm),
                Text(
                  strings.text('account.migrate.resultAlso'),
                  style: secondary,
                ),
                SizedBox(height: tokens.space.md),
                AccountInlineNotice(
                  icon: switch (view.localData) {
                    AccountMigrationLocalData.linked =>
                      StarBridgeIconSemantic.connected,
                    AccountMigrationLocalData.pending =>
                      StarBridgeIconSemantic.pending,
                    AccountMigrationLocalData.conflict =>
                      StarBridgeIconSemantic.warning,
                  },
                  textKey: switch (view.localData) {
                    AccountMigrationLocalData.linked =>
                      'account.migrate.localLinked',
                    AccountMigrationLocalData.pending =>
                      'account.migrate.localPending',
                    AccountMigrationLocalData.conflict =>
                      'account.migrate.localConflict',
                  },
                  color: view.localData == AccountMigrationLocalData.conflict
                      ? tokens.colors.warning
                      : view.localData == AccountMigrationLocalData.linked
                      ? tokens.colors.success
                      : tokens.colors.stateAccent,
                  background:
                      view.localData == AccountMigrationLocalData.conflict
                      ? tokens.colors.warningSoft
                      : view.localData == AccountMigrationLocalData.linked
                      ? tokens.colors.successSoft
                      : tokens.colors.stateAccentSoft,
                ),
                SizedBox(height: tokens.space.md),
                Text(
                  strings.text('account.migrate.oldVersions'),
                  style: secondary,
                ),
              ] else
                Text(
                  strings.text(
                    retryable
                        ? 'account.migrate.failed'
                        : 'account.migrate.recoveryRequired',
                  ),
                  style: body,
                ),
              SizedBox(height: tokens.space.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (retryable) ...[
                    StarBridgeActionButton(
                      kind: StarBridgeActionKind.quiet,
                      controlKey: const Key('account-migrate-later'),
                      onActivate: onClose,
                      child: Text(strings.text('account.migrate.later')),
                    ),
                    SizedBox(width: tokens.space.sm),
                    StarBridgeActionButton(
                      kind: StarBridgeActionKind.primary,
                      controlKey: const Key('account-migrate-result-retry'),
                      onActivate: onRetry,
                      child: Text(strings.text('account.migrate.retry')),
                    ),
                  ] else
                    StarBridgeActionButton(
                      kind: StarBridgeActionKind.primary,
                      controlKey: const Key('account-migrate-done'),
                      onActivate: onClose,
                      child: Text(strings.text('account.migrate.done')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The session the shown result belongs to: [generation] is taken when the
/// caller decides to show it.
typedef AccountMigrationResultOwner = ({
  ValueListenable<AccountProjection> account,
  int generation,
});

/// [owner]: the result belongs to that session; the dialog closes itself when
/// it ends or another account signs in, even before its first frame.
Future<void> showAccountMigrationResult(
  BuildContext context,
  AccountMigrationView view, {
  AccountMigrationResultOwner? owner,
  InteractionSource? source,
  void Function(InteractionSource source)? onRetry,
}) {
  Widget build(BuildContext dialogContext) => AccountMigrationResult(
    view: view,
    onClose: (source) =>
        dismissStarBridgeDialog<void>(dialogContext, source: source),
    onRetry: onRetry == null
        ? null
        : (source) {
            dismissStarBridgeDialog<void>(dialogContext, source: source);
            onRetry(source);
          },
  );
  return owner == null
      ? showStarBridgeDialog<void>(context, source: source, builder: build)
      : showAccountBoundDialog<void>(
          context,
          account: owner.account,
          generation: owner.generation,
          source: source,
          builder: build,
        );
}
