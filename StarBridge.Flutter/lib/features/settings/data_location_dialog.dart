import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routing/exit_application_intent.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'data_location_copy.dart';
import 'data_location_port.dart';

Future<void> showDataLocationDialog(
  BuildContext context,
  DataLocationPort port,
) async {
  final canExit = Actions.maybeFind<ExitApplicationIntent>(context) != null;
  final choice = await showDialog<DataLocationMigrationChoice>(
    context: context,
    builder: (_) => DataLocationDialog(port: port, exitAvailable: canExit),
  );
  if (choice == null ||
      !context.mounted ||
      port is! DataLocationMigrationPort) {
    return;
  }
  Actions.maybeInvoke(
    context,
    ExitApplicationIntent(
      beforeExit: () async {
        try {
          await port.confirmMigration(choice.ticket);
          return true;
        } on Object catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  dataLocationCopy(
                    context,
                    error is BridgeClientException &&
                            error.code == 'dataLocation.wpf_running'
                        ? 'migrationWpfRunning'
                        : 'migrationStartFailed',
                  ),
                ),
              ),
            );
          }
          return false;
        }
      },
    ),
  );
}

class DataLocationDialog extends StatefulWidget {
  const DataLocationDialog({
    required this.port,
    this.exitAvailable = false,
    super.key,
  });
  final DataLocationPort port;
  final bool exitAvailable;

  @override
  State<DataLocationDialog> createState() => _DataLocationDialogState();
}

class _DataLocationDialogState extends State<DataLocationDialog> {
  DataLocation? _location;
  bool _loading = true;
  bool _busy = false;
  String? _feedback;
  int _revision = 0;
  Timer? _retryTimer;
  int _failedReads = 0;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(DataLocationDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port) unawaited(_read());
  }

  Future<void> _read() async {
    _retryTimer?.cancel();
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _location = null;
      _feedback = null;
      _busy = false;
    });
    DataLocation? location;
    try {
      location = await widget.port.read();
    } on Object {
      /* Render retry, never raw errors. */
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _location = location;
      _loading = false;
    });
    if (location == null) {
      const delays = [2, 5, 15, 30];
      final seconds = delays[_failedReads.clamp(0, delays.length - 1)];
      _failedReads++;
      _retryTimer = Timer(Duration(seconds: seconds), _read);
    } else {
      _failedReads = 0;
    }
  }

  Future<void> _act(bool copy) async {
    final location = _location;
    if (_busy || location == null) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    var feedback = copy ? 'copied' : 'opened';
    try {
      if (copy) {
        await Clipboard.setData(ClipboardData(text: location.path));
      } else {
        await widget.port.open();
      }
    } on Object {
      feedback = copy ? 'copyFailed' : 'openFailed';
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _busy = false;
      _feedback = feedback;
    });
  }

  Future<void> _chooseMigration() async {
    final port = widget.port;
    if (_busy ||
        port is! DataLocationMigrationPort ||
        !port.migrationAvailable) {
      return;
    }
    final revision = _revision;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final choice = await port.chooseMigration();
      if (!mounted || revision != _revision) return;
      if (choice == null) {
        setState(() => _busy = false);
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('data-location-confirm-dialog'),
          title: Text(dataLocationCopy(dialogContext, 'confirmTitle')),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(dataLocationCopy(dialogContext, 'confirmBody')),
                SizedBox(height: dialogContext.tokens.space.md),
                Text(
                  dataLocationCopy(dialogContext, 'from'),
                  style: Theme.of(dialogContext).textTheme.labelLarge,
                ),
                SelectableText(choice.source),
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: dialogContext.tokens.space.sm,
                  ),
                  child: const StarBridgeIcon(
                    StarBridgeIconSemantic.menuDown,
                    size: 18,
                  ),
                ),
                Text(
                  dataLocationCopy(dialogContext, 'to'),
                  style: Theme.of(dialogContext).textTheme.labelLarge,
                ),
                SelectableText(choice.destination),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dataLocationCopy(dialogContext, 'keep')),
            ),
            FilledButton(
              key: const Key('data-location-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dataLocationCopy(dialogContext, 'migrate')),
            ),
          ],
        ),
      );
      if (!mounted || revision != _revision) return;
      if (confirmed == true) {
        Navigator.of(context).pop(choice);
      } else {
        setState(() => _busy = false);
      }
    } on Object {
      if (mounted && revision == _revision) {
        setState(() {
          _busy = false;
          _feedback = 'migrationChooseFailed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String t(String key) => dataLocationCopy(context, key);
    final location = _location;
    return AlertDialog(
      key: const Key('data-location-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(t('title')),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (location == null)
              Text(t('failed'))
            else ...[
              Text(t('path'), style: Theme.of(context).textTheme.labelLarge),
              SizedBox(height: tokens.space.sm),
              SelectableText(
                location.path,
                key: const Key('data-location-path'),
              ),
              if (!location.exists) ...[
                SizedBox(height: tokens.space.sm),
                Text(
                  t('missing'),
                  style: TextStyle(color: tokens.colors.warning),
                ),
              ],
              SizedBox(height: tokens.space.md),
              Wrap(
                spacing: tokens.space.sm,
                runSpacing: tokens.space.sm,
                children: [
                  FilledButton(
                    key: const Key('data-location-open'),
                    onPressed: _busy || !location.exists
                        ? null
                        : () => _act(false),
                    child: Text(t('open')),
                  ),
                  OutlinedButton(
                    key: const Key('data-location-copy'),
                    onPressed: _busy ? null : () => _act(true),
                    child: Text(t('copy')),
                  ),
                ],
              ),
            ],
            if (_feedback != null)
              Padding(
                padding: EdgeInsets.only(top: tokens.space.sm),
                child: Semantics(liveRegion: true, child: Text(t(_feedback!))),
              ),
            SizedBox(height: tokens.space.md),
            OutlinedButton(
              key: const Key('data-location-move'),
              onPressed:
                  _busy ||
                      _loading ||
                      _location?.exists != true ||
                      !widget.exitAvailable ||
                      widget.port is! DataLocationMigrationPort ||
                      !(widget.port as DataLocationMigrationPort)
                          .migrationAvailable
                  ? null
                  : _chooseMigration,
              style: OutlinedButton.styleFrom(
                disabledForegroundColor: tokens.colors.textSecondary,
              ),
              child: Text(t('move')),
            ),
          ],
        ),
      ),
      actions: [
        if (!_loading && _location == null)
          TextButton(onPressed: _busy ? null : _read, child: Text(t('retry'))),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('close')),
        ),
      ],
    );
  }
}
