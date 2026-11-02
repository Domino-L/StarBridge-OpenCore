import 'package:flutter/foundation.dart';

import '../presence/connected_manual_presence.dart';
import '../presence/manual_presence.dart';
import '../../features/official_fleet/bridge_official_fleet_members_adapter.dart';
import '../../features/official_fleet/official_fleet_members_module.dart';
import '../../features/official_fleet/official_fleet_members_port.dart';
import '../../features/settings/local_privacy_controller.dart';

/// Reuses the chrome's confirmed presence and saved main-fleet consent.
/// No reads, writes, timers or identity matching are introduced here.
void bindOfficialFleetSelfPresence(
  OfficialFleetMembersModule members,
  ManualPresenceController? presence,
  LocalPrivacyController? privacy,
) {
  if (presence == null) return;
  members.bindSelfPresence(Listenable.merge([presence, privacy]), (sourceRef) {
    bool? allowed;
    if (privacy?.status == LocalPrivacyStatus.ready) {
      final scope = privacy!.officialScope;
      if (!privacy.savedPublicationEnabled ||
          privacy.publicationView.state == 'withdrawn' ||
          privacy.publicationView.state == 'withdrawalPending') {
        allowed = false;
      } else if (scope?.state == 'available') {
        allowed =
            scope!.savedForCurrentSource &&
            scope.sourceRef == sourceRef &&
            scope.savedFields & 1 != 0;
        if (allowed &&
            (!privacy.publicationObserved ||
                privacy.publicationReadFailures > 0 ||
                privacy.publicationView.state != 'applied' ||
                privacy.publicationView.revision != privacy.revision)) {
          allowed = null;
        }
      }
    }
    return OfficialFleetSelfPresence(
      key: presence.selfKey,
      sharingAllowed: allowed,
    );
  });
}

/// The members board's whole presence wiring: this client's own row and the
/// connection mode that gates the member reads.
void bindOfficialFleetPresence(
  OfficialFleetMembersModule members,
  OfficialFleetMembersPort? port,
  ConnectedManualPresence? presence,
  LocalPrivacyController? privacy,
) {
  bindOfficialFleetSelfPresence(members, presence?.source.controller, privacy);
  if (port case final BridgeOfficialFleetMembersAdapter adapter) {
    if (presence?.connectionMode case final mode?) {
      adapter.bindConnectionMode(mode);
    }
  }
}
