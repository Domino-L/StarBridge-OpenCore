import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'account_models.dart';
import 'account_module.dart';
import 'account_port.dart';
import 'account_view_components.dart';
import 'password_recovery_dialog.dart';

class AccountCompatibilityCard extends StatelessWidget {
  const AccountCompatibilityCard({
    required this.projection,
    required this.module,
    this.readOnly = false,
    this.existingAccountOnly = false,
    super.key,
  });

  final AccountProjection projection;
  final AccountModule module;
  final bool readOnly;
  final bool existingAccountOnly;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final compatibility = projection.compatibility;
    final operation = projection.operation;
    final mutating =
        operation == AccountOperation.linkingLegacyAccount ||
        operation == AccountOperation.creatingCompatibilityIdentity ||
        operation == AccountOperation.cancellingCompatibilityOperation;
    final linked =
        compatibility.identityState == AccountCompatibilityIdentityState.linked;
    final available = compatibility.legacyFeaturesAvailable;
    final color = available
        ? tokens.colors.success
        : linked
        ? tokens.colors.warning
        : tokens.colors.accent;
    final background = available
        ? tokens.colors.successSoft
        : linked
        ? tokens.colors.warningSoft
        : tokens.colors.accentSoft;

    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountCardHeading(
            semantic: StarBridgeIconSemantic.account,
            titleKey: 'account.compatibility.title',
            bodyKey: 'account.compatibility.body',
            color: color,
          ),
          if (module.passwordRecovery case final recovery?)
            TextButton(
              key: const Key('account-linked-password-recovery'),
              onPressed: projection.isBusy
                  ? null
                  : () => unawaited(
                      showPasswordRecoveryDialog(context, recovery),
                    ),
              child: Text(strings.text('account.recovery.title')),
            ),
          SizedBox(height: tokens.space.md),
          AccountInlineNotice(
            icon: available
                ? StarBridgeIconSemantic.connected
                : linked
                ? StarBridgeIconSemantic.warning
                : StarBridgeIconSemantic.account,
            textKey: _stateTextKey(compatibility),
            color: color,
            background: background,
          ),
          if (!readOnly &&
              !existingAccountOnly &&
              compatibility.storedLegacyCredentialAvailable &&
              !linked) ...[
            SizedBox(height: tokens.space.sm),
            Text(
              strings.text('account.compatibility.savedCredential'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ],
          if (readOnly || (existingAccountOnly && !mutating)) ...[
            SizedBox(height: tokens.space.md),
            OutlinedButton.icon(
              key: const Key('account-compatibility-refresh'),
              onPressed: projection.isBusy
                  ? null
                  : () => unawaited(module.refresh()),
              icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
              label: Text(strings.text('account.compatibility.refreshAction')),
            ),
          ],
          if (!readOnly && mutating) ...[
            SizedBox(height: tokens.space.md),
            OutlinedButton.icon(
              key: const Key('account-compatibility-cancel'),
              onPressed:
                  operation == AccountOperation.cancellingCompatibilityOperation
                  ? null
                  : () => unawaited(module.cancelCompatibilityOperation()),
              icon: const StarBridgeIcon(StarBridgeIconSemantic.windowClose),
              label: Text(
                strings.text(
                  operation == AccountOperation.cancellingCompatibilityOperation
                      ? 'account.compatibility.cancelling'
                      : 'account.compatibility.cancel',
                ),
              ),
            ),
          ] else if (!readOnly &&
              (projection.canLinkLegacyAccount ||
                  (!existingAccountOnly &&
                      projection.canCreateCompatibilityIdentity) ||
                  projection.canRetryCompatibility)) ...[
            SizedBox(height: tokens.space.md),
            Wrap(
              spacing: tokens.space.sm,
              runSpacing: tokens.space.sm,
              children: [
                if (projection.canLinkLegacyAccount)
                  FilledButton.icon(
                    key: const Key('account-compatibility-link'),
                    onPressed: () => unawaited(
                      _linkExisting(
                        context,
                        forceManualCredential: existingAccountOnly,
                      ),
                    ),
                    icon: const StarBridgeIcon(StarBridgeIconSemantic.login),
                    label: Text(
                      strings.text(
                        !existingAccountOnly &&
                                compatibility.storedLegacyCredentialAvailable
                            ? 'account.compatibility.continueSaved'
                            : 'account.compatibility.linkAction',
                      ),
                    ),
                  ),
                if (!existingAccountOnly &&
                    projection.canLinkLegacyAccount &&
                    compatibility.storedLegacyCredentialAvailable)
                  OutlinedButton.icon(
                    key: const Key('account-compatibility-link-manual'),
                    onPressed: () => unawaited(
                      _linkExisting(context, forceManualCredential: true),
                    ),
                    icon: const StarBridgeIcon(StarBridgeIconSemantic.account),
                    label: Text(
                      strings.text('account.compatibility.verifyManually'),
                    ),
                  ),
                if (!existingAccountOnly &&
                    projection.canCreateCompatibilityIdentity)
                  OutlinedButton.icon(
                    key: const Key('account-compatibility-create'),
                    onPressed: () => unawaited(_createIdentity(context)),
                    icon: const StarBridgeIcon(StarBridgeIconSemantic.add),
                    label: Text(
                      strings.text('account.compatibility.createAction'),
                    ),
                  ),
                if (projection.canRetryCompatibility)
                  OutlinedButton.icon(
                    key: const Key('account-compatibility-retry'),
                    onPressed: () => unawaited(module.refresh()),
                    icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                    label: Text(
                      strings.text('account.compatibility.retryAction'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _stateTextKey(AccountCompatibilityProjection compatibility) {
    if (compatibility.identityState ==
        AccountCompatibilityIdentityState.unavailable) {
      return 'account.compatibility.unavailable';
    }
    if (compatibility.legacyFeaturesAvailable) {
      return 'account.compatibility.ready';
    }
    if (compatibility.relayState ==
        AccountCompatibilityRelayState.authorizationRequired) {
      return 'account.compatibility.authorizationRequired';
    }
    if (compatibility.relayState ==
        AccountCompatibilityRelayState.accountMismatch) {
      return 'account.compatibility.accountMismatch';
    }
    if (compatibility.relayState ==
        AccountCompatibilityRelayState.unavailable) {
      return 'account.compatibility.relayUnavailable';
    }
    return switch (compatibility.identityState) {
      AccountCompatibilityIdentityState.unavailable =>
        'account.compatibility.unavailable',
      AccountCompatibilityIdentityState.unlinked =>
        'account.compatibility.unlinked',
      AccountCompatibilityIdentityState.linked =>
        'account.compatibility.linkedRelayPending',
      AccountCompatibilityIdentityState.unknown =>
        'account.compatibility.unknown',
    };
  }

  Future<void> _linkExisting(
    BuildContext context, {
    bool forceManualCredential = false,
  }) async {
    if (projection.compatibility.storedLegacyCredentialAvailable &&
        !forceManualCredential) {
      await module.linkLegacyAccount();
      return;
    }
    final credential = await showLegacyAccountCredentialDialog(context);
    if (credential == null) {
      return;
    }
    await module.linkLegacyAccount(
      accountName: credential.accountName,
      password: credential.password,
    );
  }

  Future<void> _createIdentity(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _CreateCompatibilityIdentityDialog(),
    );
    if (confirmed == true) {
      await module.createCompatibilityIdentity();
    }
  }
}

Future<LegacyAccountCredential?> showLegacyAccountCredentialDialog(
  BuildContext context, {
  bool forMigration = false,
}) {
  return showDialog<LegacyAccountCredential>(
    context: context,
    builder: (context) =>
        _LegacyAccountCredentialDialog(forMigration: forMigration),
  );
}

class _LegacyAccountCredentialDialog extends StatefulWidget {
  const _LegacyAccountCredentialDialog({this.forMigration = false});
  final bool forMigration;

  @override
  State<_LegacyAccountCredentialDialog> createState() =>
      _LegacyAccountCredentialDialogState();
}

class _LegacyAccountCredentialDialogState
    extends State<_LegacyAccountCredentialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _accountNameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.clear();
    _passwordController.dispose();
    _accountNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: StarBridgeSurface(
          role: SurfaceRole.floating,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.text(
                          widget.forMigration
                              ? 'migration.dialogTitle'
                              : 'account.compatibility.dialog.title',
                        ),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      key: const Key('account-legacy-dialog-close'),
                      tooltip: strings.text(
                        'account.compatibility.dialog.close',
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const StarBridgeIcon(
                        StarBridgeIconSemantic.windowClose,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tokens.space.sm),
                Text(
                  strings.text(
                    widget.forMigration
                        ? 'migration.dialogBody'
                        : 'account.compatibility.dialog.body',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
                SizedBox(height: tokens.space.lg),
                TextFormField(
                  key: const Key('account-legacy-name'),
                  controller: _accountNameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: strings.text(
                      'account.compatibility.dialog.accountName',
                    ),
                  ),
                  validator: (value) => value?.trim().isNotEmpty == true
                      ? null
                      : strings.text('account.compatibility.dialog.required'),
                ),
                SizedBox(height: tokens.space.md),
                TextFormField(
                  key: const Key('account-legacy-password'),
                  controller: _passwordController,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: strings.text(
                      'account.compatibility.dialog.password',
                    ),
                  ),
                  validator: (value) => value?.isNotEmpty == true
                      ? null
                      : strings.text('account.compatibility.dialog.required'),
                ),
                SizedBox(height: tokens.space.md),
                AccountInlineNotice(
                  icon: StarBridgeIconSemantic.account,
                  textKey: widget.forMigration
                      ? 'migration.passwordNotice'
                      : 'account.compatibility.dialog.security',
                  color: tokens.colors.accent,
                  background: tokens.colors.accentSoft,
                ),
                SizedBox(height: tokens.space.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        strings.text('account.compatibility.dialog.cancel'),
                      ),
                    ),
                    SizedBox(width: tokens.space.sm),
                    FilledButton(
                      key: const Key('account-legacy-submit'),
                      onPressed: _submit,
                      child: Text(
                        strings.text(
                          widget.forMigration
                              ? 'migration.verifyPreview'
                              : 'account.compatibility.dialog.submit',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    final credential = LegacyAccountCredential(
      accountName: _accountNameController.text.trim(),
      password: _passwordController.text,
    );
    _passwordController.clear();
    Navigator.of(context).pop(credential);
  }
}

class _CreateCompatibilityIdentityDialog extends StatelessWidget {
  const _CreateCompatibilityIdentityDialog();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: StarBridgeSurface(
          role: SurfaceRole.floating,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.text('account.compatibility.createDialog.title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.space.sm),
              Text(
                strings.text('account.compatibility.createDialog.body'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
              SizedBox(height: tokens.space.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      strings.text('account.compatibility.dialog.cancel'),
                    ),
                  ),
                  SizedBox(width: tokens.space.sm),
                  FilledButton(
                    key: const Key('account-compatibility-create-confirm'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      strings.text(
                        'account.compatibility.createDialog.confirm',
                      ),
                    ),
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
