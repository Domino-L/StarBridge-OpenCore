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
import 'account_operation_motion.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_dialog_owner.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

class AccountCompatibilityCard extends StatefulWidget {
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
  State<AccountCompatibilityCard> createState() =>
      _AccountCompatibilityCardState();
}

class _AccountCompatibilityCardState extends State<AccountCompatibilityCard> {
  AccountProjection get projection => widget.projection;
  AccountModule get module => widget.module;
  bool get readOnly => widget.readOnly;
  bool get existingAccountOnly => widget.existingAccountOnly;
  bool _askingCredential = false;
  bool _isCurrent(AccountModule owner, int generation) =>
      mounted &&
      identical(owner, module) &&
      owner.projection.value.generation == generation;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final compatibility = projection.compatibility;
    final operation = projection.operation;
    final owner = module, generation = projection.generation;
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
        : tokens.colors.stateAccent;
    final background = available
        ? tokens.colors.successSoft
        : linked
        ? tokens.colors.warningSoft
        : tokens.colors.stateAccentSoft;

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
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: const Key('account-linked-password-recovery'),
              onActivate: projection.isBusy
                  ? null
                  : (source) {
                      bool current() =>
                          _isCurrent(owner, generation) &&
                          identical(owner.passwordRecovery, recovery);
                      if (!current() || owner.projection.value.isBusy) return;
                      unawaited(
                        showPasswordRecoveryDialog(
                          context,
                          recovery,
                          source: source,
                          isCurrent: current,
                          ownerChanges: owner.projection,
                        ),
                      );
                    },
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
            StarBridgeActionButton(
              controlKey: const Key('account-compatibility-refresh'),
              onActivate: projection.isBusy
                  ? null
                  : (source) {
                      if (!_isCurrent(owner, generation) ||
                          owner.projection.value.isBusy) {
                        return;
                      }
                      unawaited(
                        runAccountMotionCommand(
                          owner,
                          AccountOperation.refreshing,
                          source,
                          owner.refresh,
                        ),
                      );
                    },
              child: _actionContent(
                context,
                StarBridgeIconSemantic.refresh,
                strings.text('account.compatibility.refreshAction'),
              ),
            ),
          ],
          if (!readOnly && mutating) ...[
            SizedBox(height: tokens.space.md),
            SizedBox(width: 56, child: AccountOperationWaiting(module: owner)),
            SizedBox(height: tokens.space.sm),
            StarBridgeActionButton(
              controlKey: const Key('account-compatibility-cancel'),
              onActivate:
                  operation == AccountOperation.cancellingCompatibilityOperation
                  ? null
                  : (source) {
                      if (!_isCurrent(owner, generation) ||
                          !owner
                              .projection
                              .value
                              .canCancelCompatibilityOperation) {
                        return;
                      }
                      unawaited(
                        runAccountMotionCommand(
                          owner,
                          AccountOperation.cancellingCompatibilityOperation,
                          source,
                          owner.cancelCompatibilityOperation,
                        ),
                      );
                    },
              child: _actionContent(
                context,
                StarBridgeIconSemantic.windowClose,
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
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.primary,
                    controlKey: const Key('account-compatibility-link'),
                    onActivate: (source) => unawaited(
                      _linkExisting(
                        context,
                        source: source,
                        expectedOwner: owner,
                        generation: generation,
                        forceManualCredential: existingAccountOnly,
                      ),
                    ),
                    child: _actionContent(
                      context,
                      StarBridgeIconSemantic.login,
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
                      _linkExisting(
                        context,
                        forceManualCredential: true,
                        expectedOwner: owner,
                        generation: generation,
                      ),
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
                    onPressed: () =>
                        unawaited(_createIdentity(context, owner, generation)),
                    icon: const StarBridgeIcon(StarBridgeIconSemantic.add),
                    label: Text(
                      strings.text('account.compatibility.createAction'),
                    ),
                  ),
                if (projection.canRetryCompatibility)
                  StarBridgeActionButton(
                    controlKey: const Key('account-compatibility-retry'),
                    onActivate: (source) {
                      if (!_isCurrent(owner, generation) ||
                          !owner.projection.value.canRetryCompatibility) {
                        return;
                      }
                      unawaited(
                        runAccountMotionCommand(
                          owner,
                          AccountOperation.refreshing,
                          source,
                          owner.refresh,
                        ),
                      );
                    },
                    child: _actionContent(
                      context,
                      StarBridgeIconSemantic.refresh,
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
    InteractionSource source = InteractionSource.pointer,
    AccountModule? expectedOwner,
    int? generation,
  }) async {
    final owner = expectedOwner ?? module,
        version = generation ?? projection.generation;
    bool current() =>
        _isCurrent(owner, version) &&
        !readOnly &&
        owner.projection.value.isSignedIn &&
        owner.projection.value.compatibility.availableActions.contains(
          AccountCompatibilityAction.linkExistingAccount,
        );
    if (!current() ||
        _askingCredential ||
        !owner.projection.value.canLinkLegacyAccount) {
      return;
    }
    if (projection.compatibility.storedLegacyCredentialAvailable &&
        !forceManualCredential) {
      await runAccountMotionCommand(
        owner,
        AccountOperation.linkingLegacyAccount,
        source,
        owner.linkLegacyAccount,
      );
      return;
    }
    LegacyAccountCredential? credential;
    var completingSource = source;
    _askingCredential = true;
    try {
      credential = await showLegacyAccountCredentialDialog(
        context,
        source: source,
        isCurrent: current,
        canSubmit: () =>
            current() && owner.projection.value.canLinkLegacyAccount,
        ownerChanges: owner.projection,
        onSubmitSource: (value) => completingSource = value,
      );
    } finally {
      _askingCredential = false;
    }
    final accepted = credential;
    if (accepted == null ||
        !current() ||
        !owner.projection.value.canLinkLegacyAccount) {
      return;
    }
    await runAccountMotionCommand(
      owner,
      AccountOperation.linkingLegacyAccount,
      completingSource,
      () => owner.linkLegacyAccount(
        accountName: accepted.accountName,
        password: accepted.password,
      ),
    );
  }

  Future<void> _createIdentity(
    BuildContext context,
    AccountModule owner,
    int generation,
  ) async {
    bool current() =>
        _isCurrent(owner, generation) &&
        !readOnly &&
        !existingAccountOnly &&
        owner.projection.value.canCreateCompatibilityIdentity;
    if (!current()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _CreateCompatibilityIdentityDialog(),
    );
    if (confirmed == true && current()) {
      await owner.createCompatibilityIdentity();
    }
  }
}

Future<LegacyAccountCredential?> showLegacyAccountCredentialDialog(
  BuildContext context, {
  bool forMigration = false,
  InteractionSource? source,
  bool Function()? isCurrent,
  bool Function()? canSubmit,
  Listenable? ownerChanges,
  ValueChanged<InteractionSource>? onSubmitSource,
}) {
  final current = isCurrent ?? () => context.mounted;
  return showStarBridgeDialog<LegacyAccountCredential>(
    context,
    source: source,
    builder: (_) {
      Widget editor() => _LegacyAccountCredentialDialog(
        forMigration: forMigration,
        isCurrent: current,
        canSubmit: canSubmit ?? current,
        onSubmitSource: onSubmitSource,
      );
      return StarBridgeDialogOwnerGuard(
        isCurrent: current,
        child: ownerChanges == null
            ? editor()
            : AnimatedBuilder(
                animation: ownerChanges,
                builder: (_, _) => editor(),
              ),
      );
    },
  );
}

class _LegacyAccountCredentialDialog extends StatefulWidget {
  const _LegacyAccountCredentialDialog({
    this.forMigration = false,
    required this.isCurrent,
    required this.canSubmit,
    this.onSubmitSource,
  });
  final bool forMigration;
  final bool Function() isCurrent;
  final bool Function() canSubmit;
  final ValueChanged<InteractionSource>? onSubmitSource;

  @override
  State<_LegacyAccountCredentialDialog> createState() =>
      _LegacyAccountCredentialDialogState();
}

class _LegacyAccountCredentialDialogState
    extends State<_LegacyAccountCredentialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _accountNameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitted = false, _invalid = false;

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
            child: SingleChildScrollView(
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
                      StarBridgeIconAction(
                        controlKey: const Key('account-legacy-dialog-close'),
                        label: strings.text(
                          'account.compatibility.dialog.close',
                        ),
                        onActivate: _close,
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
                  StarBridgeFieldFrame(
                    error:
                        _invalid && _accountNameController.text.trim().isEmpty,
                    builder: (_, focus) => TextFormField(
                      key: const Key('account-legacy-name'),
                      controller: _accountNameController,
                      focusNode: focus,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: strings.text(
                          'account.compatibility.dialog.accountName',
                        ),
                      ),
                      validator: (value) => value?.trim().isNotEmpty == true
                          ? null
                          : strings.text(
                              'account.compatibility.dialog.required',
                            ),
                    ),
                  ),
                  SizedBox(height: tokens.space.md),
                  StarBridgeFieldFrame(
                    error: _invalid && _passwordController.text.isEmpty,
                    builder: (_, focus) => TextFormField(
                      key: const Key('account-legacy-password'),
                      controller: _passwordController,
                      focusNode: focus,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) =>
                          _submit(InteractionSource.keyboard),
                      decoration: InputDecoration(
                        labelText: strings.text(
                          'account.compatibility.dialog.password',
                        ),
                      ),
                      validator: (value) => value?.isNotEmpty == true
                          ? null
                          : strings.text(
                              'account.compatibility.dialog.required',
                            ),
                    ),
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
                      StarBridgeActionButton(
                        kind: StarBridgeActionKind.quiet,
                        controlKey: const Key('account-legacy-dialog-cancel'),
                        onActivate: _close,
                        child: Text(
                          strings.text('account.compatibility.dialog.cancel'),
                        ),
                      ),
                      SizedBox(width: tokens.space.sm),
                      StarBridgeActionButton(
                        kind: StarBridgeActionKind.primary,
                        controlKey: const Key('account-legacy-submit'),
                        onActivate: widget.canSubmit() ? _submit : null,
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
      ),
    );
  }

  void _close(InteractionSource source) {
    if (!mounted || _submitted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _submitted = true;
    _passwordController.clear();
    dismissStarBridgeDialog<LegacyAccountCredential>(context, source: source);
  }

  void _submit(InteractionSource source) {
    if (!mounted ||
        _submitted ||
        !widget.isCurrent() ||
        !widget.canSubmit() ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (_formKey.currentState?.validate() != true) {
      setState(() => _invalid = true);
      return;
    }
    final credential = LegacyAccountCredential(
      accountName: _accountNameController.text.trim(),
      password: _passwordController.text,
    );
    _passwordController.clear();
    _submitted = true;
    widget.onSubmitSource?.call(source);
    dismissStarBridgeDialog(context, result: credential, source: source);
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

Widget _actionContent(
  BuildContext context,
  StarBridgeIconSemantic icon,
  String label,
) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    StarBridgeIcon(icon),
    SizedBox(width: context.tokens.space.xs),
    Flexible(child: Text(label)),
  ],
);
