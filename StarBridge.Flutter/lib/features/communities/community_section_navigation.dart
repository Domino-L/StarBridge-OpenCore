import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/shell/widgets/attention_badge.dart';
import '../../design_system/interaction/starbridge_choice_navigation.dart';
import '../common/organization_holo_choice.dart';

import 'community_workspace_copy.dart';

/// Shared client/menu presentation. Callers retain capability and leave guards.
class CommunitySectionNavigation extends StatelessWidget {
  const CommunitySectionNavigation({
    required this.sections,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.chatUnreadCount = 0,
    this.changeSource,
    this.skewed = false,
    super.key,
  });

  final Map<String, bool> sections;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool enabled;
  final int chatUnreadCount;
  final InteractionSource? changeSource;

  /// Holo tabs on the organization page; menus and rooms keep the plain ones.
  final bool skewed;

  @override
  Widget build(BuildContext context) => StarBridgeChoiceNavigation(
    selected: selected,
    onSelected: onSelected,
    changeSource: changeSource,
    faceBuilder: skewed ? organizationHoloNavigationFace : null,
    choices: [
      for (final item in sections.entries)
        StarBridgeNavigationChoice(
          id: item.key,
          label:
              '${workspaceText(context, 'section.${item.key}')}'
              '${item.key == 'chat' && chatUnreadCount > 0 ? ', $chatUnreadCount' : ''}',
          enabled: enabled && item.value,
          hint: item.value ? '' : workspaceText(context, 'sectionUnavailable'),
          controlKey: ValueKey('community-section-${item.key}'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(workspaceText(context, 'section.${item.key}')),
              if (item.key == 'chat' && chatUnreadCount > 0) ...[
                const SizedBox(width: 6),
                AttentionCount(count: chatUnreadCount),
              ],
            ],
          ),
        ),
    ],
  );
}
