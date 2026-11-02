import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../features/settings/bridge_data_location_result.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'startup_prompt_queue.dart';
import 'storage_result_presentation.dart';
import 'storage_result_retry.dart';

/// Reads the Host's data-location migration result once per connection,
/// shows it through the startup prompt queue and acknowledges it. Failed
/// reads, a missing navigator and failed receipts retry for the same Host
/// revision only.
final class StorageMigrationResultFlow {
  StorageMigrationResultFlow({
    required this.retry,
    required this.prompts,
    required this.isCurrent,
    required this.ready,
    required this.context,
  });

  final StorageResultRetry retry;
  final StartupPromptQueue prompts;

  /// Not disposed and still the given Host revision.
  final bool Function(int revision) isCurrent;

  /// The startup prompts may show now.
  final bool Function() ready;
  final BuildContext? Function() context;

  void read(BridgeClientSession session, int revision) {
    if (!isCurrent(revision)) return;
    if (!session.hostCapabilities.contains('dataLocation.getMigrationResult') ||
        !session.hostCapabilities.contains(
          'dataLocation.acknowledgeMigrationResult',
        )) {
      return;
    }
    unawaited(() async {
      DataLocationMigrationResult? result;
      try {
        result = await BridgeDataLocationResult(session).read();
      } on Object {
        retry.schedule(revision, () => read(session, revision));
        return;
      }
      if (result == null || !isCurrent(revision)) return;
      final migrationResult = result;
      final key = 'storage-migration-result-${migrationResult.nonce}';
      prompts.enqueue(
        key,
        priority: 20,
        eligible: () => ready() && isCurrent(revision),
        show: () async {
          final current = context();
          if (current == null || !current.mounted) {
            retry.schedule(revision, () => read(session, revision));
            return;
          }
          final controller = showStorageMigrationResult(
            current,
            migrationResult.state,
          );
          if (controller == null) {
            retry.schedule(revision, () => read(session, revision));
            return;
          }
          await _acknowledge(session, revision, migrationResult.nonce);
          await controller.closed;
        },
      );
    }());
  }

  Future<void> _acknowledge(
    BridgeClientSession session,
    int revision,
    String nonce,
  ) async {
    if (!isCurrent(revision)) return;
    try {
      await BridgeDataLocationResult(session).acknowledge(nonce);
    } on Object {
      // Retry only the receipt: the user has already seen the result.
      retry.schedule(
        revision,
        () => unawaited(_acknowledge(session, revision, nonce)),
      );
    }
  }
}
