import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'help_support_waiting.dart';
import 'maintenance_action.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'application_support_module.dart';
import 'application_support_models.dart';
import 'diagnostics_maintenance_text.dart';
import 'image_cache_maintenance_controller.dart';

class DiagnosticsMaintenancePanel extends StatefulWidget {
  const DiagnosticsMaintenancePanel({
    required this.support,
    this.session,
    this.imageMaintenance,
    super.key,
  });
  final ApplicationSupportModule support;
  final BridgeClientSession? session;
  final ImageCacheMaintenanceController? imageMaintenance;
  @override
  State<DiagnosticsMaintenancePanel> createState() =>
      _DiagnosticsMaintenancePanelState();
}

class _DiagnosticsMaintenancePanelState
    extends State<DiagnosticsMaintenancePanel> {
  bool _busy = false;
  String? _result;
  bool _failed = false;
  bool _confirming = false;
  InteractionSource _waitSource = InteractionSource.programmatic;
  int _waitPhase = 0;
  String _waitLabel = 'opening';
  bool get _operationBusy => _busy || widget.imageMaintenance?.busy == true;

  void _maintenanceChanged() {
    if (!mounted) return;
    setState(() {
      _result = widget.imageMaintenance?.result;
      _failed = _result == 'failed';
      if (widget.imageMaintenance?.busy == true) _waitLabel = 'clearing';
    });
  }

  @override
  void initState() {
    super.initState();
    widget.imageMaintenance?.addListener(_maintenanceChanged);
    _result = widget.imageMaintenance?.result;
    _failed = _result == 'failed';
    if (widget.imageMaintenance?.busy == true) _waitLabel = 'clearing';
  }

  @override
  void didUpdateWidget(covariant DiagnosticsMaintenancePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageMaintenance != widget.imageMaintenance) {
      oldWidget.imageMaintenance?.removeListener(_maintenanceChanged);
      widget.imageMaintenance?.addListener(_maintenanceChanged);
      _result = widget.imageMaintenance?.result;
      _failed = _result == 'failed';
      if (widget.imageMaintenance?.busy == true) _waitLabel = 'clearing';
    }
  }

  @override
  void dispose() {
    widget.imageMaintenance?.removeListener(_maintenanceChanged);
    super.dispose();
  }

  Future<void> _run(String action) => runStarBridgeActivation<void>(
    captureStarBridgeActivationSource()(),
    () async {
      if (_operationBusy) return;
      setState(() {
        _busy = true;
        _confirming = action == 'clearImageCache';
        _waitSource = captureStarBridgeActivationSource()();
        _waitPhase++;
        _waitLabel = 'opening';
      });
      try {
        if (action == 'clearImageCache') {
          final confirmed = await showStarBridgeDialog<bool>(
            context,
            builder: (context) => AlertDialog(
              title: Text(maintenanceText(context, 'clear')),
              content: Text(maintenanceText(context, 'confirm')),
              actions: [
                MaintenanceAction(
                  TextButton(
                    key: const Key('maintenance-confirm-cancel'),
                    onPressed: () => dismissStarBridgeDialog<bool>(
                      context,
                      source: captureStarBridgeActivationSource()(),
                      result: false,
                    ),
                    child: Text(maintenanceText(context, 'cancel')),
                  ),
                ),
                MaintenanceAction(
                  FilledButton(
                    key: const Key('maintenance-confirm-execute'),
                    onPressed: () => dismissStarBridgeDialog<bool>(
                      context,
                      source: captureStarBridgeActivationSource()(),
                      result: true,
                    ),
                    child: Text(maintenanceText(context, 'clear')),
                  ),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
          setState(() {
            _confirming = false;
            _waitSource = captureStarBridgeActivationSource()();
            _waitPhase++;
            _waitLabel = 'clearing';
          });
        }
        if (action == 'openDataDirectory') {
          if (await widget.support.openDataDirectory() !=
              ApplicationSupportActionResult.completed) {
            throw StateError('unavailable');
          }
        } else if (action == 'clearImageCache' &&
            widget.imageMaintenance != null) {
          await widget.imageMaintenance!.clear();
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
        if (mounted) {
          setState(() {
            _busy = false;
            _confirming = false;
          });
        }
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    bool available(String name) =>
        !_operationBusy &&
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
          if (_result != null)
            Padding(
              padding: EdgeInsets.only(top: tokens.space.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  maintenanceText(context, _result!),
                  style: TextStyle(
                    color: _failed
                        ? tokens.colors.warning
                        : tokens.colors.success,
                  ),
                ),
              ),
            ),
          Text(maintenanceText(context, 'scope')),
          SizedBox(height: tokens.space.md),
          if (_operationBusy && !_confirming)
            HelpSupportWaiting(
              key: ValueKey(('maintenance', _waitPhase)),
              label: maintenanceText(context, _waitLabel),
              source: _waitSource,
            ),
          Wrap(
            spacing: tokens.space.sm,
            runSpacing: tokens.space.sm,
            children: [
              MaintenanceAction(
                OutlinedButton(
                  key: const Key('maintenance-open-folder'),
                  onPressed: available('openDataDirectory')
                      ? () => _run('openDataDirectory')
                      : null,
                  child: Text(maintenanceText(context, 'folder')),
                ),
              ),
              MaintenanceAction(
                OutlinedButton(
                  key: const Key('maintenance-clear-cache'),
                  onPressed: available('clearImageCache')
                      ? () => _run('clearImageCache')
                      : null,
                  child: Text(maintenanceText(context, 'clear')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
