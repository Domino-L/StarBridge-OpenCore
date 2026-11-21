import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'account_migration.dart';
import 'account_view_components.dart';

/// Replaces the legacy data card while the relay offers migration. With the
/// switch off ([AccountMigrationState.unavailable]) callers keep the old card.
class AccountMigrationCard extends StatelessWidget {
  const AccountMigrationCard({
    required this.view,
    this.onMigrate,
    this.onRetry,
    this.onShowResult,
    super.key,
  });

  final AccountMigrationView view;
  final void Function(InteractionSource source)? onMigrate;
  final void Function(InteractionSource source)? onRetry;
  final void Function(InteractionSource source)? onShowResult;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final (color, background, icon, textKey) = switch (view.state) {
      AccountMigrationState.completed => (
        tokens.colors.success,
        tokens.colors.successSoft,
        StarBridgeIconSemantic.connected,
        'account.migrate.completed',
      ),
      AccountMigrationState.failed => (
        tokens.colors.warning,
        tokens.colors.warningSoft,
        StarBridgeIconSemantic.warning,
        'account.migrate.failed',
      ),
      AccountMigrationState.recoveryRequired => (
        tokens.colors.warning,
        tokens.colors.warningSoft,
        StarBridgeIconSemantic.warning,
        'account.migrate.recoveryRequired',
      ),
      AccountMigrationState.migrating => (
        tokens.colors.stateAccent,
        tokens.colors.stateAccentSoft,
        StarBridgeIconSemantic.pending,
        view.stillWorking
            ? 'account.migrate.stillWorking'
            : 'account.migrate.migrating',
      ),
      _ => (
        tokens.colors.stateAccent,
        tokens.colors.stateAccentSoft,
        StarBridgeIconSemantic.account,
        'account.migrate.notLinked',
      ),
    };
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountCardHeading(
            semantic: StarBridgeIconSemantic.account,
            titleKey: 'account.migrate.title',
            bodyKey: 'account.migrate.body',
            color: color,
          ),
          SizedBox(height: tokens.space.md),
          AccountInlineNotice(
            icon: icon,
            textKey: textKey,
            color: color,
            background: background,
          ),
          if (view.state == AccountMigrationState.migrating &&
              !view.stillWorking) ...[
            SizedBox(height: tokens.space.sm),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (view.state == AccountMigrationState.completed) ...[
            SizedBox(height: tokens.space.sm),
            Text(
              strings.text('account.migrate.oldVersions'),
              key: const Key('account-migrate-old-versions'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ],
          if (_action(strings) case final action?) ...[
            SizedBox(height: tokens.space.md),
            Align(alignment: AlignmentDirectional.centerStart, child: action),
          ],
        ],
      ),
    );
  }

  Widget? _action(AppStrings strings) => switch (view.state) {
    AccountMigrationState.notLinked => StarBridgeActionButton(
      kind: StarBridgeActionKind.primary,
      controlKey: const Key('account-migrate-start'),
      onActivate: onMigrate,
      child: _content(
        StarBridgeIconSemantic.login,
        strings.text('account.migrate.action'),
      ),
    ),
    AccountMigrationState.failed => StarBridgeActionButton(
      kind: StarBridgeActionKind.primary,
      controlKey: const Key('account-migrate-retry'),
      onActivate: onRetry,
      child: _content(
        StarBridgeIconSemantic.refresh,
        strings.text('account.migrate.retry'),
      ),
    ),
    AccountMigrationState.completed when view.resultAvailable =>
      StarBridgeActionButton(
        kind: StarBridgeActionKind.quiet,
        controlKey: const Key('account-migrate-show-result'),
        onActivate: onShowResult,
        child: Text(strings.text('account.migrate.showResult')),
      ),
    _ => null,
  };

  Widget _content(StarBridgeIconSemantic icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [StarBridgeIcon(icon), const SizedBox(width: 8), Text(label)],
  );
}
