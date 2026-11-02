import 'package:flutter/material.dart';

import '../../app/shell/widgets/attention_badge.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'friends_module.dart';

/// Presentation of the original side list. No selection or request owner.
class FriendsSectionNavigation extends StatelessWidget {
  const FriendsSectionNavigation({
    required this.module,
    required this.label,
    required this.onSection,
    required this.onRecent,
    required this.showRecent,
    required this.recentUnread,
    super.key,
  });
  final FriendsModule module;
  final String Function(String) label;
  final ValueChanged<FriendsSection> onSection;
  final VoidCallback onRecent;
  final bool showRecent;
  final int recentUnread;

  String _sectionLabel(FriendsSection section) {
    final title = label(section.name);
    if (module.searching || module.snapshot == null) return title;
    final count = module.snapshot!.groups[section]?.length ?? 0;
    return section == FriendsSection.incoming && count == 0
        ? title
        : '$title\n$count';
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      if (showRecent) ...[
        StarBridgeActionRow(
          controlKey: const Key('friends-recent'),
          baseRadius: 0,
          semanticLabel:
              '${label('recent')}${recentUnread > 0 ? '\n$recentUnread' : ''}',
          onActivate: module.busy ? null : (_, _) => onRecent(),
          child: ExcludeSemantics(
            child: ListTile(
              title: Text(
                label('recent'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              trailing: AttentionCount(count: recentUnread),
            ),
          ),
        ),
        const Divider(),
      ],
      for (final section in FriendsSection.values)
        StarBridgeActionRow(
          controlKey: ValueKey('friends-nav-${section.name}'),
          baseRadius: 0,
          semanticLabel: _sectionLabel(section),
          semanticSelected: !module.searching && module.section == section,
          onActivate: module.busy ? null : (_, _) => onSection(section),
          child: ExcludeSemantics(
            child: ListTile(
              title: Text(
                label(section.name),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              trailing: !module.searching && module.snapshot != null
                  ? section == FriendsSection.incoming
                        ? AttentionCount(
                            count:
                                module.snapshot!.groups[section]?.length ?? 0,
                          )
                        : Text(
                            '${module.snapshot!.groups[section]?.length ?? 0}',
                          )
                  : null,
              selected: !module.searching && module.section == section,
              selectedTileColor: context.tokens.surfaces.selected.fill,
              selectedColor: context.tokens.colors.accent,
            ),
          ),
        ),
    ],
  );
}
