import '../../features/common/organization_hangar_sharing.dart';
import '../../features/communities/community_ships_port.dart';
import '../../features/official_fleet/bridge_official_fleet_hangar_sharing.dart';
import '../../features/official_fleet/bridge_official_fleet_shared_ships.dart';
import '../../features/official_fleet/official_fleet_module.dart';
import '../../features/official_fleet/unavailable_official_fleet_shared_ships.dart';
import '../../features/onboarding/connection_mode_port.dart';
import '../../features/settings/bridge_local_privacy.dart';
import '../../features/settings/local_privacy_controller.dart';
import '../../platform/bridge/bridge_client_session.dart';

/// Local privacy follows the official fleet's source; none without a host.
LocalPrivacyController? composeLocalPrivacy(
  BridgeClientSession? session,
  OfficialFleetModule officialFleet,
) => session == null
    ? null
    : LocalPrivacyController(
        BridgeLocalPrivacy(
          session,
          officialSourceChanges: officialFleet.projection,
          officialContextRevision: () => (
            officialFleet.contextRevision,
            officialFleet.projection.value.fleet?.sourceRef,
          ),
        ),
      );

/// The official fleet's shared-ship read and own hangar sharing ports, both
/// following the connection mode. Overrides (tests, review) win.
({CommunityShipsPort sharedShips, OrganizationHangarSharingPort? ownSharing})
composeOfficialFleetSharing(
  BridgeClientSession? session,
  OfficialFleetModule officialFleet, {
  CommunityShipsPort? sharedShipsOverride,
  OrganizationHangarSharingPort? ownSharingOverride,
  ConnectionModeControl? connectionMode,
}) => (
  sharedShips:
      sharedShipsOverride ??
      (session == null
          ? const UnavailableOfficialFleetSharedShips()
          : BridgeOfficialFleetSharedShips(
              session,
              sourceRef: () => officialFleet.projection.value.fleet?.sourceRef,
              sourceChanges: officialFleet.projection,
              connectionMode: connectionMode,
            )),
  ownSharing:
      ownSharingOverride ??
      (session == null
          ? null
          : BridgeOfficialFleetHangarSharing(
              session,
              connectionMode: connectionMode,
            )),
);
