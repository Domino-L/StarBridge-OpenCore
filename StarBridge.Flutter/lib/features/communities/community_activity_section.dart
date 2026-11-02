import 'package:flutter/material.dart';

import '../common/organization_activity_page.dart';
import '../common/social_read_activity.dart';
import 'community_announcements_dialog.dart';
import 'community_announcements_port.dart';
import 'community_workspace_controller.dart';
import 'community_workspace_copy.dart';

bool communityActivityAvailable(Object port) =>
    port is CommunityAnnouncementsPort && port.announcementsAvailable;

/// 组织活动: announcements and their history. Communities have no rally, so
/// nothing stands in for one.
class CommunityActivitySection extends StatelessWidget {
  const CommunityActivitySection({
    required this.port,
    required this.model,
    super.key,
  });

  final CommunityAnnouncementsPort port;
  final CommunityWorkspaceController model;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsetsDirectional.only(end: 16),
    child: OrganizationActivityPage(
      title: workspaceText(context, 'activity.title'),
      children: [
        CommunityAnnouncementEntry(
          key: ValueKey('activity-announcements:${model.targetRef}'),
          controller: model.announcements,
          port: port,
          targetRef: model.targetRef,
          expanded: true,
        ),
      ],
    ),
  );
}

/// The workspace's thin read indicator.
Widget communityRefreshProgress(
  CommunityWorkspaceController model,
  SocialReadActivityBinding activity,
  String label,
) => SizedBox(
  height: 2,
  child: model.showProgress
      ? KeyedSubtree(
          key: ValueKey((model, activity.revision)),
          child: SocialReadActivity(
            key: const ValueKey('community-refresh-progress'),
            source: activity.source,
            opening: false,
            label: label,
          ),
        )
      : null,
);
