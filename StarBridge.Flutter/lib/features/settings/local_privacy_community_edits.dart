import 'package:flutter/foundation.dart';

import 'community_sharing.dart';
import 'local_privacy_settings.dart';

/// Community choices and legacy grant projection on the local privacy draft.
/// Reads, save authority and publication remain with the controller.
mixin LocalPrivacyCommunityEdits on ChangeNotifier {
  LocalPrivacySettings? get draft;
  CommunitySharingTargets? get communityTargets;
  bool get communityTargetsFailed;
  bool get canEdit;
  bool get hasSaved;
  void edit(LocalPrivacySettings value);

  /// Explicitly bind legacy organization choices to their current membership.
  /// The closed main-fleet feature is separate and receives no authority here.
  LocalPrivacySettings bindCommunityChoices(
    LocalPrivacySettings value, {
    bool preserveExistingOrganizationChoice = true,
  }) {
    final targets = communityTargets;
    if (value.communities != null ||
        targets == null ||
        communityTargetsFailed) {
      return value;
    }
    final primary = targets.communities
        .where((t) => t.code == targets.primaryFleetCode)
        .firstOrNull;
    return value.copyWith(
      communities: [
        if (primary != null && preserveExistingOrganizationChoice)
          CommunitySharingScope(
            code: primary.code,
            joinedAt: primary.joinedAt,
            fields: value.fleetFields & 15,
            administratorsCanView: value.fleetAdministratorsCanView,
            allMembersCanView: value.fleetAllMembersCanView,
            visibilityGroupIds: value.fleetVisibilityGroupIds,
          ),
      ],
    );
  }

  void enableCommunityChoices() {
    if (canEdit) {
      edit(
        bindCommunityChoices(
          draft!,
          preserveExistingOrganizationChoice: hasSaved,
        ),
      );
    }
  }

  void editCommunity(CommunitySharingScope value) {
    if (!canEdit ||
        draft?.communities == null ||
        communityTargetsFailed ||
        !(communityTargets?.communities.any((t) => t.matches(value)) ??
            false)) {
      return;
    }
    edit(
      draft!.copyWith(
        communities: [
          ...draft!.communities!.where(
            (s) =>
                s.code.toLowerCase() != value.code.toLowerCase() &&
                communityTargets!.communities.any((t) => t.matches(s)),
          ),
          value,
        ],
      ),
    );
  }

  List<CommunitySharingTarget> get unconfirmedCommunities =>
      draft?.communities == null || communityTargetsFailed
      ? const []
      : (communityTargets?.communities ?? const [])
            .where((target) => !draft!.communities!.any(target.matches))
            .toList();
}
