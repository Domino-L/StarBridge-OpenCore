import 'package:flutter/material.dart';

import '../common/organization_communication.dart';
import 'official_fleet_models.dart';
import 'official_fleet_overview_models.dart';
import 'official_fleet_refresh_notice.dart';

class OfficialFleetWorkspaceSyncNotice extends StatelessWidget {
  const OfficialFleetWorkspaceSyncNotice({
    required this.projection,
    required this.overview,
    required this.communication,
    super.key,
  });
  final OfficialFleetProjection projection;
  final OfficialFleetOverviewProjection overview;
  final OrganizationCommunication communication;

  @override
  Widget build(BuildContext context) {
    final primaryFailure = projection.refreshFailed || overview.refreshFailed;
    final active =
        projection.isRefreshing ||
        projection.isProfileReading ||
        overview.isRefreshing ||
        communication.isRefreshing;
    final refreshFailed =
        primaryFailure ||
        communication.readOnly ||
        projection.profileRefreshFailed;
    // Match the community workspace's reserved two-pixel feedback slot.
    if (!active && !refreshFailed) return const SizedBox(height: 2);
    final key = primaryFailure
        ? 'officialFleet.syncFailed'
        : communication.readOnly
        ? 'officialFleet.communication.syncFailed'
        : projection.profileRetained
        ? 'officialFleet.profile.syncFailed'
        : 'officialFleet.profile.readFailed';
    final at = projection.refreshFailed
        ? projection.observedAtUtc
        : overview.refreshFailed
        ? overview.observedAtUtc
        : communication.readOnly
        ? communication.lastVerifiedAtUtc
        : projection.profileObservedAtUtc;
    return OfficialFleetRefreshNotice(
      active: active,
      refreshFailed: refreshFailed,
      failureMessageKey: key,
      lastReadAtUtc: at,
    );
  }
}
