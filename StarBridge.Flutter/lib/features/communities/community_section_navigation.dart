import 'package:flutter/material.dart';

import '../../app/shell/widgets/attention_badge.dart';

import 'community_workspace_copy.dart';

/// Shared client/menu presentation. Callers retain capability and leave guards.
class CommunitySectionNavigation extends StatelessWidget {
  const CommunitySectionNavigation({
    required this.sections,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.chatUnreadCount = 0,
    super.key,
  });

  final Map<String, bool> sections;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool enabled;
  final int chatUnreadCount;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final item in sections.entries)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Tooltip(
              message: item.value
                  ? ''
                  : workspaceText(context, 'sectionUnavailable'),
              child: ChoiceChip(
                key: ValueKey('community-section-${item.key}'),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(workspaceText(context, 'section.${item.key}')),
                    if (item.key == 'chat' && chatUnreadCount > 0) ...[
                      const SizedBox(width: 6),
                      AttentionCount(count: chatUnreadCount),
                    ],
                  ],
                ),
                showCheckmark: false,
                labelStyle: Theme.of(context).textTheme.labelLarge,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                elevation: 0,
                pressElevation: 0,
                chipAnimationStyle: ChipAnimationStyle(
                  enableAnimation: AnimationStyle.noAnimation,
                  selectAnimation: AnimationStyle.noAnimation,
                  avatarDrawerAnimation: AnimationStyle.noAnimation,
                  deleteDrawerAnimation: AnimationStyle.noAnimation,
                ),
                selected: selected == item.key,
                onSelected: enabled && item.value
                    ? (_) => onSelected(item.key)
                    : null,
              ),
            ),
          ),
      ],
    ),
  );
}
