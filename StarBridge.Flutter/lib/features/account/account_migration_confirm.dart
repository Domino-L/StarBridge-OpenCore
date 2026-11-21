import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'account_view_components.dart';

/// For an SCM account with no linked old account: the old account sign-in that
/// links it, after which the relay migrates on the next request. Same fields as
/// the existing link dialog; only the wording is about migration.
class AccountMigrationConfirm extends StatefulWidget {
  const AccountMigrationConfirm({
    this.onSubmit,
    this.onCancel,
    this.busy = false,
    super.key,
  });

  final void Function(
    String accountName,
    String password,
    InteractionSource source,
  )?
  onSubmit;
  final void Function(InteractionSource source)? onCancel;
  final bool busy;

  @override
  State<AccountMigrationConfirm> createState() =>
      _AccountMigrationConfirmState();
}

class _AccountMigrationConfirmState extends State<AccountMigrationConfirm> {
  final _name = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    // Closed by submit, cancel or a lost session: nothing typed stays behind.
    _password.clear();
    _name.clear();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit(InteractionSource source) {
    final name = _name.text.trim(), password = _password.text;
    // The field is cleared before the value leaves this dialog (an incomplete
    // form stays open with what was typed).
    if (name.isNotEmpty && password.isNotEmpty) _password.clear();
    widget.onSubmit!(name, password, source);
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.text('account.migrate.confirmTitle'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    StarBridgeIconAction(
                      controlKey: const Key('account-migrate-confirm-close'),
                      label: strings.text('account.compatibility.dialog.close'),
                      onActivate: widget.onCancel,
                      icon: const StarBridgeIcon(
                        StarBridgeIconSemantic.windowClose,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tokens.space.sm),
                Text(
                  strings.text('account.migrate.confirmBody'),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
                SizedBox(height: tokens.space.lg),
                StarBridgeFieldFrame(
                  builder: (_, focus) => TextField(
                    key: const Key('account-migrate-name'),
                    controller: _name,
                    focusNode: focus,
                    decoration: InputDecoration(
                      labelText: strings.text(
                        'account.compatibility.dialog.accountName',
                      ),
                    ),
                  ),
                ),
                SizedBox(height: tokens.space.md),
                StarBridgeFieldFrame(
                  builder: (_, focus) => TextField(
                    key: const Key('account-migrate-password'),
                    controller: _password,
                    focusNode: focus,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: strings.text(
                        'account.compatibility.dialog.password',
                      ),
                    ),
                  ),
                ),
                SizedBox(height: tokens.space.md),
                AccountInlineNotice(
                  icon: StarBridgeIconSemantic.warning,
                  textKey: 'account.migrate.confirmNotice',
                  color: tokens.colors.warning,
                  background: tokens.colors.warningSoft,
                ),
                SizedBox(height: tokens.space.sm),
                Text(
                  strings.text('account.migrate.passwordNote'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
                SizedBox(height: tokens.space.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    StarBridgeActionButton(
                      kind: StarBridgeActionKind.quiet,
                      controlKey: const Key('account-migrate-confirm-cancel'),
                      onActivate: widget.onCancel,
                      child: Text(strings.text('account.migrate.cancel')),
                    ),
                    SizedBox(width: tokens.space.sm),
                    StarBridgeActionButton(
                      kind: StarBridgeActionKind.primary,
                      controlKey: const Key('account-migrate-confirm-submit'),
                      onActivate: widget.busy || widget.onSubmit == null
                          ? null
                          : _submit,
                      child: Text(
                        strings.text('account.migrate.confirmSubmit'),
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
}
