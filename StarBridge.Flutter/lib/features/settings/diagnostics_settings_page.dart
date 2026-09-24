import '../../design_system/icons/standard_icon.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'bridge_local_event_history.dart';
import 'application_support_module.dart';
import 'application_support_page.dart';
import 'diagnostics_maintenance_panel.dart';
import 'flutter_installation_panel.dart';
import 'runtime_status_controller.dart';
import 'runtime_status_dialog.dart';
import 'local_event_clear.dart';
import 'local_event_export.dart';
import 'local_event_history.dart';
import 'local_event_history_dialog.dart';
import 'settings_capability_catalog.dart';
import 'settings_entry_catalog.dart';
import 'settings_entry_dialog.dart';

/// Owns the page's history reader, but borrows the application's Bridge session.
class DiagnosticsSettingsPage extends StatefulWidget {
  const DiagnosticsSettingsPage({
    required this.support,
    this.createRuntime,
    this.historyPort,
    this.session,
    super.key,
  });
  final ApplicationSupportModule support;
  final RuntimeStatusController Function()? createRuntime;
  final LocalHistoryPort? historyPort;
  final BridgeClientSession? session;

  @override
  State<DiagnosticsSettingsPage> createState() =>
      _DiagnosticsSettingsPageState();
}

class _DiagnosticsSettingsPageState extends State<DiagnosticsSettingsPage> {
  late LocalHistoryController _history;
  LocalEventExportPort? _export;
  LocalEventClearPort? _clear;
  RuntimeStatusController? _runtime;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _runtime = widget.createRuntime?.call();
    final session = widget.session;
    final available =
        session?.hostCapabilities.contains('diagnostics.localEvents') ?? false;
    _history = LocalHistoryController(
      widget.historyPort ??
          (session != null && available
              ? BridgeLocalEventHistory(session)
              : const LocalHistoryUnavailable()),
    );
    _export =
        session != null &&
            available &&
            session.hostCapabilities.contains('diagnostics.localEventsExport')
        ? BridgeLocalEventExport(session)
        : null;
    _clear =
        session != null &&
            available &&
            session.hostCapabilities.contains('diagnostics.localEventsClear')
        ? BridgeLocalEventClear(session)
        : null;
  }

  void _disconnect() {
    _runtime?.dispose();
    _history.dispose();
    _export?.cancel();
    _clear?.cancel();
  }

  @override
  void didUpdateWidget(DiagnosticsSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _disconnect();
      _connect();
    }
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    return SingleChildScrollView(
      key: const Key('diagnostics-settings-page'),
      padding: EdgeInsets.all(tokens.space.lg),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.density.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.text('settings.diagnostics'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.space.md),
              if (_runtime case final runtime?)
                RuntimeStatusDialog(controller: runtime, embedded: true)
              else
                _DiagnosticTool(
                  id: 'runtime-status',
                  icon: StarBridgeIconSemantic.diagnostics,
                  color: tokens.colors.info,
                ),
              SizedBox(height: tokens.space.sm),
              ApplicationSupportPanel(module: widget.support),
              SizedBox(height: tokens.space.lg),
              LocalEventHistoryDialog(
                key: ObjectKey(_history),
                controller: _history,
                exportPort: _export,
                clearPort: _clear,
                embedded: true,
              ),
              SizedBox(height: tokens.space.lg),
              DiagnosticsMaintenancePanel(
                support: widget.support,
                session: widget.session,
              ),
              SizedBox(height: tokens.space.sm),
              FlutterInstallationPanel(session: widget.session),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiagnosticTool extends StatelessWidget {
  const _DiagnosticTool({
    required this.id,
    required this.icon,
    required this.color,
  });
  final String id;
  final StarBridgeIconSemantic icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final capability = SettingsCapabilityCatalog.planned.singleWhere(
      (item) => item.id == id,
    );
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          key: Key('settings-capability-$id'),
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: EdgeInsets.all(tokens.space.sm),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: tokens.shape.small,
            ),
            child: StarBridgeIcon(icon, color: color),
          ),
          title: Text(strings.text(capability.titleKey)),
          subtitle: Text(settingsEntryText(strings, 'description.$id')),
          trailing: const StandardIcon(StandardIconSemantic.chevronRight),
          onTap: () => showSettingsCapabilityEntry(context, capability),
        ),
      ),
    );
  }
}
