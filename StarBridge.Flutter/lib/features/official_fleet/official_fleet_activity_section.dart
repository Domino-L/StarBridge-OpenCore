import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../common/organization_activity_page.dart';
import '../common/organization_announcement_outcomes_dialog.dart';
import '../common/organization_communication.dart';
import '../communities/community_announcements_copy.dart';
import 'official_fleet_models.dart';
import 'official_fleet_rally.dart';
import 'official_fleet_rally_views.dart';

/// 舰队活动: the running rally, starting one when allowed, and announcements
/// with their history. The workspace strip steps aside on this page.
class OfficialFleetActivitySection extends StatelessWidget {
  const OfficialFleetActivitySection({
    required this.rally,
    required this.communication,
    super.key,
  });

  final OfficialFleetRallyController rally;
  final OrganizationCommunication communication;

  @override
  Widget build(BuildContext context) => OrganizationActivityPage(
    title: AppStrings.of(context).text('officialFleet.activity.title'),
    children: [
      OfficialFleetRallyStrip(controller: rally),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OfficialFleetRallyStartButton(controller: rally),
      ),
      if (communication.announcementsAvailable)
        communication.announcement(expanded: true),
    ],
  );
}

/// Only where announcements are read or managed.
Widget officialFleetAnnouncementOutcomesFor(
  OrganizationCommunication communication,
  OfficialFleetWorkspaceSection section,
) => switch (section) {
  OfficialFleetWorkspaceSection.broadcasts ||
  OfficialFleetWorkspaceSection.manage => officialFleetOwnAnnouncementOutcomes(
    communication,
  ),
  _ => const SizedBox.shrink(),
};

Widget officialFleetOwnAnnouncementOutcomes(
  OrganizationCommunication communication,
) => AnimatedBuilder(
  animation: communication,
  builder: (context, _) => !communication.announcementOutcomesAvailable
      ? const SizedBox.shrink()
      : Align(
          alignment: Alignment.centerRight,
          child: StarBridgeActionButton(
            controlKey: const Key('official-fleet-announcement-outcomes'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (_) => showOrganizationAnnouncementOutcomes(
              context,
              communication.announcementOutcomes!,
            ),
            child: Text(communityAnnouncementText(context, 'ownOutcomes')),
          ),
        ),
);
