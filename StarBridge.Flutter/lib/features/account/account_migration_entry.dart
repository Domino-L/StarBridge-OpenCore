import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_dialog.dart';
import 'account_generation_guard.dart';
import 'account_migration.dart';
import 'account_migration_card.dart';
import 'account_migration_confirm.dart';
import 'account_migration_controller.dart';
import 'account_migration_result.dart';
import 'account_models.dart';
import 'account_module.dart';
import 'account_operation_motion.dart';
import 'account_port.dart';

/// Settings › Account & identity: the migration card while the relay offers it
/// (or the old account is already retired), otherwise the existing card.
class AccountMigrationEntry extends StatefulWidget {
  const AccountMigrationEntry({
    required this.controller,
    required this.module,
    required this.fallback,
    super.key,
  });

  final AccountMigrationController controller;
  final AccountModule module;
  final Widget fallback;

  @override
  State<AccountMigrationEntry> createState() => _AccountMigrationEntryState();
}

class _AccountMigrationEntryState extends State<AccountMigrationEntry> {
  bool _asking = false;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AccountMigrationView>(
        valueListenable: widget.controller,
        builder: (context, view, _) => view.offered
            ? AccountMigrationCard(
                view: view,
                onMigrate: _asking || widget.controller.busy ? null : _migrate,
                onRetry: widget.controller.busy ? null : _retry,
                onShowResult: (source) => unawaited(_showResult(source)),
              )
            : widget.fallback,
      );

  Future<void> _migrate(InteractionSource source) async {
    final module = widget.module, controller = widget.controller;
    final generation = module.projection.value.generation;
    bool current() =>
        mounted &&
        module.projection.value.generation == generation &&
        module.projection.value.canLinkLegacyAccount;
    if (!current()) return;
    _asking = true;
    LegacyAccountCredential? credential;
    var submitted = source;
    try {
      // Signed out or another session: the dialog closes and drops the input.
      credential = await showAccountBoundDialog<LegacyAccountCredential>(
        context,
        account: module.projection,
        generation: generation,
        source: source,
        builder: (dialog) => AccountMigrationConfirm(
          onCancel: (source) =>
              dismissStarBridgeDialog<LegacyAccountCredential>(
                dialog,
                source: source,
              ),
          onSubmit: (name, password, source) {
            if (name.isEmpty || password.isEmpty) return;
            submitted = source;
            dismissStarBridgeDialog<LegacyAccountCredential>(
              dialog,
              source: source,
              result: LegacyAccountCredential(
                accountName: name,
                password: password,
              ),
            );
          },
        ),
      );
    } finally {
      _asking = false;
    }
    if (credential == null || !current()) return;
    final AccountActionResult linked;
    try {
      final link = credential;
      linked = await runAccountMotionCommand(
        module,
        AccountOperation.linkingLegacyAccount,
        submitted,
        () => module.linkLegacyAccount(
          accountName: link.accountName,
          password: link.password,
        ),
      );
    } finally {
      // Held only for the sign-in itself, not while the status is read.
      credential = null;
    }
    // Linked now, so canLinkLegacyAccount is false: only the session must match.
    if (linked.outcome != AccountActionOutcome.completed ||
        !_sameSession(generation)) {
      return;
    }
    // The relay migrates on the next session read, which this refresh runs.
    await controller.load(refresh: true);
    if (_sameSession(generation) && controller.resultPending) {
      await _showResult(submitted, generation: generation);
    }
  }

  Future<void> _retry(InteractionSource source) async {
    final generation = widget.module.projection.value.generation;
    await widget.controller.retry();
    if (_sameSession(generation) && widget.controller.resultPending) {
      await _showResult(source, generation: generation);
    }
  }

  bool _sameSession(int generation) =>
      mounted &&
      widget.module.projection.value.isSignedIn &&
      widget.module.projection.value.generation == generation;

  Future<void> _showResult(InteractionSource source, {int? generation}) async {
    final controller = widget.controller;
    // The session the result belongs to, fixed now rather than at first frame.
    final owner = generation ?? widget.module.projection.value.generation;
    if (!_sameSession(owner) || !controller.value.offered) return;
    // One result dialog at a time, shared with the startup prompt; showing
    // marks it, so neither shows it a second time.
    await controller.present(
      (view) => showAccountMigrationResult(
        context,
        view,
        owner: (account: widget.module.projection, generation: owner),
        source: source,
        onRetry: view.state == AccountMigrationState.failed ? _retry : null,
      ),
    );
  }
}
