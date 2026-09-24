import 'package:flutter/material.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'application_support_module.dart';
import 'application_support_models.dart';
import 'diagnostics_maintenance_text.dart';

class DiagnosticsMaintenancePanel extends StatefulWidget {
  const DiagnosticsMaintenancePanel({
    required this.support,
    this.session,
    super.key,
  });
  final ApplicationSupportModule support;
  final BridgeClientSession? session;
  @override
  State<DiagnosticsMaintenancePanel> createState() =>
      _DiagnosticsMaintenancePanelState();
}

class _DiagnosticsMaintenancePanelState
    extends State<DiagnosticsMaintenancePanel> {
  bool _busy = false;
  String? _result;
  bool _failed = false;

  Future<void> _run(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (action == 'clearImageCache') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(maintenanceText(context, 'clear')),
            content: Text(maintenanceText(context, 'confirm')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(maintenanceText(context, 'cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(maintenanceText(context, 'clear')),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      if (action == 'openDataDirectory') {
        if (await widget.support.openDataDirectory() !=
            ApplicationSupportActionResult.completed) {
          throw StateError('unavailable');
        }
      } else {
        final response = await widget.session!.request(
          'diagnostics.$action',
          payload: {'schemaVersion': 1},
        );
        final p = response.payload;
        if (p.length != 2 ||
            p['schemaVersion'] != 1 ||
            (action == 'clearImageCache'
                ? p['count'] is! int || (p['count'] as int) < 0
                : p['opened'] != true)) {
          throw StateError('invalid');
        }
      }
      if (mounted) {
        setState(() {
          _result = action == 'clearImageCache' ? 'cleared' : 'opened';
          _failed = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _result = 'failed';
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    bool available(String name) =>
        !_busy &&
        (widget.session?.hostCapabilities.contains('diagnostics.$name') ??
            false);
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            maintenanceText(context, 'title'),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: tokens.colors.warning),
          ),
          SizedBox(height: tokens.space.sm),
          Text(maintenanceText(context, 'scope')),
          SizedBox(height: tokens.space.md),
          Wrap(
            spacing: tokens.space.sm,
            runSpacing: tokens.space.sm,
            children: [
              OutlinedButton(
                onPressed: available('openDataDirectory')
                    ? () => _run('openDataDirectory')
                    : null,
                child: Text(maintenanceText(context, 'folder')),
              ),
              OutlinedButton(
                key: const Key('maintenance-clear-cache'),
                onPressed: available('clearImageCache')
                    ? () => _run('clearImageCache')
                    : null,
                child: Text(maintenanceText(context, 'clear')),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_result != null)
            Padding(
              padding: EdgeInsets.only(top: tokens.space.sm),
              child: Text(
                maintenanceText(context, _result!),
                style: TextStyle(
                  color: _failed
                      ? tokens.colors.warning
                      : tokens.colors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
