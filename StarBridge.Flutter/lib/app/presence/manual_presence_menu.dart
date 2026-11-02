import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_cascading_menu.dart';
import '../../shared/release/official_client_profile.dart';
import 'manual_presence.dart';
import 'manual_presence_widgets.dart';

// Read-only menu projection shared by the existing account and tray surfaces.
// Every command, availability gate and confirmed value stays with its owner.
List<StarBridgeCascadeEntry> manualPresenceEntries(
  BuildContext context,
  ManualPresenceController controller,
) {
  final tokens = context.tokens;
  Widget body(
    String label,
    Color color,
    bool selected,
    String id,
    bool enabled,
  ) => Row(
    children: [
      DecoratedBox(
        key: ValueKey('manual-presence-dot-$id'),
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: const SizedBox.square(dimension: 8),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? color : color.withValues(alpha: .45),
          ),
        ),
      ),
      if (selected)
        const StarBridgeIcon(StarBridgeIconSemantic.connected, size: 16)
      else
        const SizedBox(width: 16),
    ],
  );
  return [
    for (final mode in [
      PresenceVisibility.online,
      PresenceVisibility.invisible,
    ])
      StarBridgeCascadeEntry(
        id: 'manual-presence-${mode.name}',
        keepOpen: true,
        label: manualPresenceText(
          context,
          mode == PresenceVisibility.online
              ? OfficialClientProfile.connectionModes &&
                        (controller.isOffline ||
                            controller
                                    .connectionMode
                                    ?.snapshot
                                    .needsOnlineRecovery ==
                                true)
                    ? 'presence.resumeOnline'
                    : 'presence.selectOnline'
              : 'presence.invisible',
        ),
        selected:
            !controller.isOffline &&
            (controller.connectionMode?.allowsOnlineTraffic ?? true) &&
            controller.snapshot.confirmedMode == mode,
        onActivate:
            mode == PresenceVisibility.online && controller.canRestoreOnline
            ? (_) => unawaited(controller.restoreOnline())
            : controller.canChange
            ? (_) => unawaited(controller.select(mode))
            : null,
        child: body(
          manualPresenceText(
            context,
            mode == PresenceVisibility.online
                ? OfficialClientProfile.connectionModes &&
                          (controller.isOffline ||
                              controller
                                      .connectionMode
                                      ?.snapshot
                                      .needsOnlineRecovery ==
                                  true)
                      ? 'presence.resumeOnline'
                      : 'presence.selectOnline'
                : 'presence.invisible',
          ),
          mode == PresenceVisibility.online
              ? tokens.colors.info
              : tokens.colors.offline,
          !controller.isOffline &&
              (controller.connectionMode?.allowsOnlineTraffic ?? true) &&
              controller.snapshot.confirmedMode == mode,
          mode.name,
          mode == PresenceVisibility.online && controller.canRestoreOnline ||
              controller.canChange,
        ),
      ),
    if (OfficialClientProfile.connectionModes)
      StarBridgeCascadeEntry(
        id: 'manual-presence-offline',
        label: manualPresenceText(context, 'presence.selectOffline'),
        keepOpen: true,
        selected: controller.isOffline,
        onActivate: controller.canEnterOffline
            ? (_) => unawaited(controller.selectOffline())
            : null,
        child: body(
          manualPresenceText(context, 'presence.selectOffline'),
          tokens.colors.danger,
          controller.isOffline,
          'offline',
          controller.canEnterOffline,
        ),
      ),
  ];
}

Widget? manualPresenceMenuFeedback(
  BuildContext context,
  ManualPresenceController controller,
) => controller.busy || controller.failed || !controller.canChange
    ? Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          manualPresenceText(
            context,
            controller.busy
                ? 'presence.working'
                : controller.failed
                ? 'presence.failed'
                : 'presence.unavailable',
          ),
          key: const Key('manual-presence-feedback'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: controller.failed
                ? context.tokens.colors.warning
                : context.tokens.colors.textSecondary,
          ),
        ),
      )
    : null;
