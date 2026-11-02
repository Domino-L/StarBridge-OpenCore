import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'community_ship_report_controller.dart';
import 'community_ship_report_editor.dart';
import 'community_ship_report_port.dart';
import 'community_ships_port.dart';
import 'community_ships_copy.dart';

/// One report route, with the existing immutable report intent. A dispatched
/// receipt survives the workspace; an unsent draft remains detail-scoped.
class CommunityShipReportDialog extends StatefulWidget {
  const CommunityShipReportDialog({
    required this.port,
    required this.ships,
    required this.targetRef,
    required this.shipRef,
    required this.version,
    required this.shipName,
    required this.parentRetirements,
    super.key,
  });
  final CommunityShipReportPort port;
  final CommunityShipsPort ships;
  final String targetRef, shipRef, version, shipName;
  final Stream<void> parentRetirements;
  @override
  State<CommunityShipReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<CommunityShipReportDialog> {
  late final model = CommunityShipReportController(
    widget.port,
    widget.targetRef,
    widget.shipRef,
    widget.version,
  );
  late final StreamSubscription<void> _scope, _parent;
  StreamSubscription<void>? _receipt;
  bool _confirming = false, _retiring = false;
  String t(String key) => communityShipsText(context, key);
  @override
  void initState() {
    super.initState();
    model.addListener(_changed);
    _scope = widget.ships.invalidations.listen((_) => _retireSource());
    _parent = widget.parentRetirements.listen((_) => _retireSource());
    if (widget.port case final CommunityShipReportReceiptScope owner) {
      _receipt = owner.reportReceiptRetirements.listen((_) => _retireRoute());
    }
  }

  void _changed() {
    if (mounted && !_retiring) setState(() {});
  }

  void _retireSource() {
    if (_retiring || !mounted) return;
    if (model.intent == null) {
      _retireRoute();
      return;
    }
    model.retireSource();
  }

  void _retireRoute() {
    if (_retiring) return;
    _retiring = true;
    model.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route is StarBridgeDialogRoute) retireStarBridgeDialog(route);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _close() {
    if (model.busy || _retiring) return;
    if (model.dirty) {
      setState(() => _confirming = true);
      return;
    }
    dismissStarBridgeDialog(context);
  }

  @override
  void dispose() {
    model.removeListener(_changed);
    if (!_retiring) model.dispose();
    unawaited(_scope.cancel());
    unawaited(_parent.cancel());
    unawaited(_receipt?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
    child: Focus(
      autofocus: true,
      child: PopScope(
        canPop: !model.busy && (!model.dirty || _confirming),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: AlertDialog(
          key: const Key('community-ship-report-dialog'),
          title: Text(t('reportTitle')),
          content: SizedBox(
            width: 620,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (model.sourceRetired)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      t('reportSourceRetired'),
                      key: const Key('ship-report-source-retired'),
                    ),
                  ),
                Expanded(
                  child: CommunityShipReportEditor(
                    model: model,
                    shipName: model.sourceRetired ? '' : widget.shipName,
                    confirmingClose: _confirming,
                    onKeepEditing: () => setState(() => _confirming = false),
                    onDiscard: () => dismissStarBridgeDialog(context),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            StarBridgeActionButton(
              controlKey: const Key('ship-report-close'),
              onActivate: model.busy ? null : (_) => _close(),
              child: Text(t('close')),
            ),
          ],
        ),
      ),
    ),
  );
}
