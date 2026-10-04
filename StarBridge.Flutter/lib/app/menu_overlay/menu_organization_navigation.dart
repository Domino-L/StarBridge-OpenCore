import 'package:flutter/material.dart';

import '../../features/communities/community_section_navigation.dart';
import '../../features/communities/community_workspace_copy.dart';
import 'menu_feature_view.dart';

/// Presentation-only adapter. Opaque commands stay scoped to the primary session.
class MenuOrganizationNavigation extends StatelessWidget {
  const MenuOrganizationNavigation({
    required this.view,
    required this.onAction,
    super.key,
  });
  final MenuFeatureView view;
  final void Function(String, String) onAction;

  @override
  Widget build(BuildContext context) {
    final org = view.organization!;
    return Row(
      children: [
        Expanded(
          child: CommunitySectionNavigation(
            sections: {
              for (final id in const [
                'members',
                'chat',
                'ships',
                'announcements',
              ])
                if (org.sections.containsKey(id)) id: true,
            },
            enabled:
                !view.busy && org.sections.values.every((key) => key != null),
            selected: org.tab,
            onSelected: (id) {
              if (id != org.tab && org.sections[id] != null) {
                onAction(org.sections[id]!, '');
              }
            },
          ),
        ),
        TextButton(
          onPressed: view.busy ? null : () => onAction('refresh', ''),
          child: Text(workspaceText(context, 'refresh')),
        ),
      ],
    );
  }
}
