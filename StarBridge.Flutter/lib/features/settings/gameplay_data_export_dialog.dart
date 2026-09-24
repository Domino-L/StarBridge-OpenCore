import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../account/account_models.dart';
import 'bridge_gameplay_data_export.dart';
import 'gameplay_data_export_panel.dart';
import 'gameplay_data_export_port.dart';
import 'settings_capability_catalog.dart';
import 'settings_entry_catalog.dart';

Future<void> showGameplayDataExportDialog(
  BuildContext context,
  ValueListenable<AccountProjection> account,
  BridgeClientSession? session,
) => showDialog<void>(
  context: context,
  builder: (_) => GameplayDataExportDialog(account: account, session: session),
);

/// Owns only the dialog's account-bound adapter, never the shared Bridge session.
class GameplayDataExportDialog extends StatefulWidget {
  const GameplayDataExportDialog({
    required this.account,
    this.session,
    super.key,
  });
  final ValueListenable<AccountProjection> account;
  final BridgeClientSession? session;

  @override
  State<GameplayDataExportDialog> createState() =>
      _GameplayDataExportDialogState();
}

class _GameplayDataExportDialogState extends State<GameplayDataExportDialog> {
  GameplayDataExportPort _port = const UnavailableGameplayDataExport();
  (AccountSessionState, int, int?)? _ownerKey;
  StreamSubscription<BridgeEnvelope>? _events;
  BridgeRequestOperation? _resolve;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_bind);
    _events = widget.session?.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _bind();
      }
    });
    _bind();
  }

  void _bind() {
    final account = widget.account.value;
    final session = widget.session;
    final key = (
      account.sessionState,
      account.generation,
      session?.activeGeneration,
    );
    if (_ownerKey == key) return;
    _ownerKey = key;
    final epoch = ++_epoch;
    _port.cancel();
    final previous = _resolve;
    _resolve = null;
    if (previous != null) unawaited(previous.cancel());
    setState(() => _port = const UnavailableGameplayDataExport());
    if (session == null ||
        !session.hostCapabilities.contains('gameplayTime.export') ||
        !(account.isSignedIn || account.isLegacyAccount) ||
        account.generation != session.activeGeneration) {
      return;
    }
    unawaited(_resolveOwner(session, account.generation, epoch));
  }

  Future<void> _resolveOwner(
    BridgeClientSession session,
    int generation,
    int epoch,
  ) async {
    try {
      final operation = session.beginRequest(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
        timeout: const Duration(seconds: 10),
      );
      _resolve = operation;
      final response = await operation.future;
      if (!mounted ||
          epoch != _epoch ||
          session.activeGeneration != generation) {
        return;
      }
      if (response.payload['schemaVersion'] != 1 ||
          !const [
            'signedIn',
            'legacySignedIn',
            'legacyUnavailable',
          ].contains(response.payload['state']) ||
          response.sessionGeneration != generation ||
          response.accountContext == null) {
        return;
      }
      setState(
        () =>
            _port = BridgeGameplayDataExport(session, response.accountContext!),
      );
    } on Object {
      // Keep the unavailable port; reopening retries without restoring another owner.
    } finally {
      if (epoch == _epoch) _resolve = null;
    }
  }

  @override
  void dispose() {
    ++_epoch;
    widget.account.removeListener(_bind);
    unawaited(_events?.cancel());
    final operation = _resolve;
    if (operation != null) unawaited(operation.cancel());
    _port.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    String t(String key) => settingsEntryText(strings, key);
    final capability = SettingsCapabilityCatalog.planned.singleWhere(
      (item) => item.id == 'local-data-management',
    );
    return AlertDialog(
      key: const Key('settings-entry-local-data-management'),
      scrollable: true,
      title: Text(strings.text(capability.titleKey)),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GameplayDataExportPanel(port: _port),
            SizedBox(height: tokens.space.lg),
            const Divider(),
            Text(t('unavailable')),
            SizedBox(height: tokens.space.sm),
            OutlinedButton(
              key: const Key('settings-action-local-data-management-clearData'),
              onPressed: null,
              child: Text(t('clearData')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('settings-entry-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('close')),
        ),
      ],
    );
  }
}
