import 'package:flutter/material.dart';

import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/interaction/starbridge_action_button.dart';
import '../../../design_system/interaction/starbridge_tooltip.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../localization/app_strings.dart';
import '../../runtime/sharing_status_monitor.dart';

/// Persistent, read-only status. Clicking navigates; it never changes consent.
class SharingStatusIndicator extends StatelessWidget {
  const SharingStatusIndicator({
    required this.monitor,
    required this.onOpenSettings,
    this.compact = false,
    super.key,
  });

  final SharingStatusMonitor monitor;
  final VoidCallback onOpenSettings;
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor,
    builder: (context, _) {
      final state = monitor.indicator;
      // Only a confirmed state is shown. "Pending" is never a badge (user
      // decision 2026-10-22: it appeared right after launch); a failed read
      // still shows the status notice with its retry.
      if (monitor.isOffline || state == SharingIndicatorState.unknown) {
        return const SizedBox.shrink();
      }
      final strings = AppStrings.of(context);
      final colors = context.tokens.colors;
      final label = strings.text('privacy.indicator.${state.name}');
      final color = switch (state) {
        SharingIndicatorState.sharing => colors.success,
        SharingIndicatorState.closed => colors.textSecondary,
        _ => colors.warning,
      };
      final icon = StarBridgeIcon(
        state == SharingIndicatorState.sharing
            ? StarBridgeIconSemantic.connected
            : state == SharingIndicatorState.closed
            ? StarBridgeIconSemantic.privacy
            : StarBridgeIconSemantic.warning,
        size: 14,
        color: color,
      );
      final tooltip = '$label · ${strings.text('privacy.indicator.open')}';
      return StarBridgeTooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: StarBridgeActionButton(
          controlKey: const Key('sharing-status-indicator'),
          kind: StarBridgeActionKind.quiet,
          onActivate: (_) => onOpenSettings(),
          nativeStyle: TextButton.styleFrom(foregroundColor: color),
          semanticLabel: tooltip,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              if (!compact) ...[
                const SizedBox(width: 5),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: color),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
