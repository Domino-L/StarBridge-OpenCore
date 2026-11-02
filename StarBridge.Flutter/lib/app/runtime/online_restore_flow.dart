import 'package:flutter/material.dart';

import '../../features/account/account_module.dart';
import '../../features/onboarding/bridge_online_installation_adapter.dart';
import '../../features/onboarding/bridge_online_review_adapter.dart';
import '../../features/onboarding/connection_mode_port.dart';
import '../../features/onboarding/online_restore_dialog.dart';
import '../../features/onboarding/retained_online_restore.dart';
import '../presence/connected_manual_presence.dart';
import '../../shared/release/official_client_profile.dart';

// Primary engine owns the route; menus borrow only its explicit command.
// No second account, login loop, privacy consent or first-use completion owner.
final class OnlineRestoreFlow {
  OnlineRestoreFlow({
    required this.connection,
    required this.account,
    required this.context,
    required this.current,
  }) {
    if (!OfficialClientProfile.connectionModes) return;
    final capabilities = connection.session.hostCapabilities;
    if (capabilities.contains(BridgeOnlineReviewAdapter.retainedCapability) &&
        capabilities.contains(BridgeOnlineInstallationAdapter.capability)) {
      _release = connection.source.controller.bindOnlineRestore(_open);
    }
  }
  final ConnectedManualPresence connection;
  final AccountModule account;
  final BuildContext? Function() context;
  final bool Function() current;
  VoidCallback? _release;
  bool _disposed = false, _openRoute = false;
  bool get _current => !_disposed && current();
  Future<bool> _open() async {
    final source = context();
    if (!_current ||
        _openRoute ||
        source == null ||
        !source.mounted ||
        connection.connectionMode.failed ||
        !(connection.connectionMode.snapshot.isOffline ||
            connection.connectionMode.snapshot.needsOnlineRecovery)) {
      return false;
    }
    _openRoute = true;
    final installation = BridgeOnlineInstallationAdapter(connection.session);
    try {
      final review = BridgeOnlineReviewAdapter(connection.session);
      final generation = connection.session.activeGeneration;
      bool unchanged() =>
          _current && connection.session.activeGeneration == generation;
      int? revision;
      try {
        revision = await restoreRetainedOnline(
          review: review,
          installation: installation,
          originalHandle: account.projection.value.identity.authoritativeHandle,
          current: unchanged,
        );
      } on Object {
        // No login, credential replacement or installation replay on uncertainty.
      }
      if (!_current || !source.mounted) return false;
      if (revision != null && unchanged()) {
        try {
          final result = await installation.install(revision);
          if (result.online && await _installed()) return true;
        } on Object {
          // Continue with read-only observation of the original installation.
        }
        if (!_current || !source.mounted) return false;
        return await showOnlineRestoreDialog(
          source,
          review: review,
          installation: installation,
          onInstalled: _installed,
          installationRevision: revision,
        );
      }
      if (!unchanged()) return false;
      return await showOnlineRestoreDialog(
        source,
        review: review,
        installation: installation,
        onInstalled: _installed,
      );
    } finally {
      installation.dispose();
      _openRoute = false;
      if (_current) await connection.refresh();
    }
  }

  Future<bool> _installed() async {
    if (!_current) return false;
    await connection.connectionMode.refresh();
    if (!_current ||
        connection.connectionMode.snapshot.state !=
            ConnectionModeState.online) {
      return false;
    }
    await account.refresh();
    if (!_current ||
        !account.projection.value.isSignedIn ||
        account.projection.value.generation !=
            connection.session.activeGeneration) {
      return false;
    }
    await connection.refresh();
    return _current && connection.connectionMode.allowsOnlineTraffic;
  }

  void dispose() {
    _disposed = true;
    _release?.call();
    _release = null;
  }
}
