import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

import 'community_ship_report_controller.dart';
import 'community_ship_report_port.dart';
import 'community_ships_copy.dart';

class CommunityShipReportEditor extends StatelessWidget {
  const CommunityShipReportEditor({
    required this.model,
    required this.shipName,
    required this.confirmingClose,
    required this.onKeepEditing,
    required this.onDiscard,
    super.key,
  });
  final CommunityShipReportController model;
  final String shipName;
  final bool confirmingClose;
  final VoidCallback onKeepEditing, onDiscard;
  @override
  Widget build(BuildContext context) {
    String t(String key) => communityShipsText(context, key);
    final editable = model.editable && !confirmingClose;
    final errorKey = 'reportError_${model.outcome?.error}';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(shipName, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(t('reportIntro')),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            key: const ValueKey('ship-report-reason'),
            initialValue: model.reason,
            isExpanded: true,
            decoration: InputDecoration(labelText: t('reportReason')),
            items: [
              for (final reason in CommunityShipReportIntent.reasons)
                DropdownMenuItem(
                  value: reason,
                  child: Text(t('reportReason_$reason')),
                ),
            ],
            onChanged: editable
                ? (value) => model.edit(value, model.details)
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('ship-report-details'),
            initialValue: model.details,
            style: Theme.of(context).textTheme.bodyMedium,
            enabled: editable,
            minLines: 5,
            maxLines: 8,
            maxLength: 1000,
            decoration: InputDecoration(labelText: t('reportDetails')),
            onChanged: (value) => model.edit(model.reason, value),
          ),
          if (model.outcome != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  t(
                    model.accepted
                        ? 'reportAccepted'
                        : model.unknown
                        ? 'reportUnknown'
                        : communityShipsCopy.containsKey(errorKey)
                        ? errorKey
                        : 'reportError_unavailable',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: model.accepted
                        ? context.tokens.colors.success
                        : model.unknown
                        ? context.tokens.colors.warning
                        : context.tokens.colors.danger,
                  ),
                ),
              ),
            ),
          if (confirmingClose) ...[
            const Divider(height: 24),
            Text(t(model.unknown ? 'reportCloseUnknown' : 'reportDiscardBody')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onKeepEditing,
                  child: Text(
                    t(model.unknown ? 'reportKeepQuery' : 'reportKeepEditing'),
                  ),
                ),
                TextButton(
                  onPressed: onDiscard,
                  child: Text(t(model.unknown ? 'close' : 'reportDiscard')),
                ),
              ],
            ),
          ] else if (!model.accepted)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('ship-report-submit'),
                onPressed: model.busy || model.reason == null
                    ? null
                    : model.unknown
                    ? model.check
                    : model.submit,
                child: Text(
                  t(
                    model.busy
                        ? 'reportBusy'
                        : model.unknown
                        ? 'reportCheck'
                        : 'reportSubmit',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
