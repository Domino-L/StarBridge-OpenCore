import '../../shared/guide/guide_scope.dart';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/widgets/attention_badge.dart';
import '../../design_system/interaction/starbridge_choice_navigation.dart';
import '../common/organization_holo_choice.dart';
import 'official_fleet_models.dart';
import '../communities/community_settings_workspace.dart'
    show communitySettingsText;

/// Same navigation as community organizations; the fleet owns capabilities.
class OfficialFleetWorkspaceNavigation extends StatelessWidget {
  const OfficialFleetWorkspaceNavigation({
    required this.selected,
    required this.onSelected,
    this.chatUnreadCount = 0,
    this.availableSections = const {
      OfficialFleetWorkspaceSection.members,
      OfficialFleetWorkspaceSection.ships,
    },
    super.key,
  });
  final OfficialFleetWorkspaceSection selected;
  final ValueChanged<OfficialFleetWorkspaceSection> onSelected;
  final Set<OfficialFleetWorkspaceSection> availableSections;
  final int chatUnreadCount;
  static const sections = [
    OfficialFleetWorkspaceSection.members,
    OfficialFleetWorkspaceSection.channel,
    OfficialFleetWorkspaceSection.ships,
    OfficialFleetWorkspaceSection.broadcasts,
    OfficialFleetWorkspaceSection.manage,
  ];
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String label(OfficialFleetWorkspaceSection section) =>
        section == OfficialFleetWorkspaceSection.manage
        ? communitySettingsText(context, 'title')
        : strings.text('officialFleet.tab.${section.name}');
    return StarBridgeChoiceNavigation(
      faceBuilder: organizationHoloNavigationFace,
      selected: selected.name,
      onSelected: (id) =>
          onSelected(OfficialFleetWorkspaceSection.values.byName(id)),
      choices: [
        for (final section in sections)
          StarBridgeNavigationChoice(
            id: section.name,
            label:
                '${label(section)}'
                '${section == OfficialFleetWorkspaceSection.channel && chatUnreadCount > 0 ? ', $chatUnreadCount' : ''}',
            child: GuideAnchor(
              id: 'fleet.${section.name}',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label(section)),
                  if (section == OfficialFleetWorkspaceSection.channel &&
                      availableSections.contains(section) &&
                      chatUnreadCount > 0) ...[
                    const SizedBox(width: 6),
                    AttentionCount(count: chatUnreadCount),
                  ],
                ],
              ),
            ),
            enabled: availableSections.contains(section),
            hint: availableSections.contains(section)
                ? ''
                : strings.text('officialFleet.workspace.unavailable'),
            controlKey: Key('official-fleet-tab-${section.name}'),
          ),
      ],
    );
  }
}
