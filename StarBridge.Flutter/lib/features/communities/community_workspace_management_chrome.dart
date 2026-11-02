import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import 'community_disband_copy.dart';
import 'community_ownership_exit_copy.dart';
import 'community_settings_workspace.dart' show communitySettingsText;
import 'community_workspace_copy.dart';

// Presentation only. The original workspace retains permission/capability
// checks, confirmation routes, draft protection and the actual commands.
Widget communityWorkspaceDangerActions(
  BuildContext context, {
  required bool showOwnershipExit,
  required bool showDisband,
  required bool busy,
  required Future<void> Function() onOwnershipExit,
  required Future<void> Function() onDisband,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    if (showOwnershipExit) ...[
      Align(
        alignment: Alignment.centerLeft,
        child: StarBridgeActionButton(
          controlKey: const ValueKey('leave-with-successor'),
          tone: ActionTone.warning,
          onActivate: busy ? null : (_) => onOwnershipExit(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const StandardIcon(StandardIconSemantic.logout),
              const SizedBox(width: 8),
              Text(ownershipExitText(context, 'title')),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
    ],
    if (showDisband) ...[
      Align(
        alignment: Alignment.centerLeft,
        child: StarBridgeActionButton(
          controlKey: const ValueKey('disband-community'),
          tone: ActionTone.danger,
          onActivate: busy ? null : (_) => onDisband(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const StandardIcon(StandardIconSemantic.deleteForever),
              const SizedBox(width: 8),
              Text(disbandText(context, 'action')),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
    ],
  ],
);

Widget communityWorkspaceManagementHeader(
  BuildContext context, {
  required String name,
  required Future<void> Function() onBack,
  required Future<void> Function() onRefresh,
}) => Row(
  children: [
    StarBridgeActionButton(
      kind: StarBridgeActionKind.quiet,
      controlKey: const ValueKey('community-settings-back'),
      onActivate: (_) => onBack(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StandardIcon(StandardIconSemantic.arrowBack, size: 18),
          const SizedBox(width: 8),
          Text(communitySettingsText(context, 'back')),
        ],
      ),
    ),
    const SizedBox(width: 16),
    Expanded(
      child: Text(
        name,
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
      ),
    ),
    StarBridgeIconAction(
      controlKey: const Key('community-management-refresh'),
      label: workspaceText(context, 'refresh'),
      onActivate: (_) => onRefresh(),
      icon: const StandardIcon(StandardIconSemantic.refresh),
    ),
  ],
);
