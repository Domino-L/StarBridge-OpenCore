import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../design_system/theme/classic_font_scope.dart';
import '../../features/official_fleet/bridge_official_fleet_adapter.dart';
import '../../features/official_fleet/bridge_official_fleet_communication_adapter.dart';
import '../../features/official_fleet/bridge_official_fleet_hangar_sharing.dart';
import '../../features/official_fleet/bridge_official_fleet_members_adapter.dart';
import '../../features/official_fleet/bridge_official_fleet_shared_ships.dart';
import '../../features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import '../../features/official_fleet/unavailable_official_fleet_ships_adapter.dart';
import '../../features/official_fleet/official_fleet_module.dart';
import '../../features/official_fleet/official_fleet_page.dart';
import '../../features/official_fleet/official_fleet_rally.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../shared/remote_image_loader.dart';
import 'menu_relay_page_owner.dart';

/// The client's main fleet modules, built on the relayed session exactly as
/// the client builds them. Rally hotkeys stay with the client; the first
/// sharing choice is made there too (the menu passes no privacy controller).
/// The page is not "entered" here, so the automatic governance activation
/// runs only from the client.
final class MenuFleetContent implements MenuRelayPageContent {
  MenuFleetContent(BridgeClientSession session, MenuFleetOwner owner) {
    final relay = owner.relay;
    final members = BridgeOfficialFleetMembersAdapter(session)
      ..bindConnectionMode(relay.hostMode);
    module = createOfficialFleetModule(
      BridgeOfficialFleetAdapter(session),
      UnavailableOfficialFleetOverviewAdapter(),
      members,
      UnavailableOfficialFleetShipsAdapter(),
      communicationFactory: (sourceRef) =>
          createOfficialFleetCommunicationAdapter(
            session,
            sourceRef,
            connectionMode: relay.hostMode,
            ownProfile: () => relay.ownProfile,
          ),
      // The client's rally view and its answers; rally hotkeys stay with the
      // client, which also raises the in-game alert.
      rally: OfficialFleetRallyController(
        BridgeOfficialFleetRallyPort(
          session,
          onlineTrafficAllowed: () => relay.hostMode.allowsOnlineTraffic,
        ),
        countedOnline: () => relay.countedOnline,
      ),
    );
    sharedShips = BridgeOfficialFleetSharedShips(
      session,
      sourceRef: () => module.projection.value.fleet?.sourceRef,
      sourceChanges: module.projection,
      connectionMode: relay.hostMode,
    );
    hangarSharing = BridgeOfficialFleetHangarSharing(
      session,
      connectionMode: relay.hostMode,
    );
    unawaited(module.initialize());
  }

  late final OfficialFleetModule module;
  late final BridgeOfficialFleetSharedShips sharedShips;
  late final BridgeOfficialFleetHangarSharing hangarSharing;

  @override
  void refresh() => unawaited(module.refresh());

  /// The module follows `account.changed` itself; the owner's navigator change
  /// closes the old account's dialogs.
  @override
  void contextChanged() {}

  @override
  void dispose() {
    module.dispose();
    unawaited(sharedShips.close());
    unawaited(hangarSharing.close());
  }
}

final class MenuFleetOwner extends MenuRelayPageOwner<MenuFleetContent> {
  MenuFleetOwner(super.relay);

  @override
  String get clientPage => 'openFleetPage';

  @override
  bool asksClientOnly(String name) =>
      name == 'account.refreshRsiData' ||
      name.startsWith('officialFleet.governance.');

  @override
  MenuFleetContent create(
    BridgeClientSession session,
    RemoteImageLoader images,
  ) => MenuFleetContent(session, this);
}

class MenuFleetPage extends StatelessWidget {
  const MenuFleetPage({super.key, required this.owner});
  final MenuFleetOwner owner;

  @override
  Widget build(BuildContext context) => MenuRelayPage<MenuFleetContent>(
    owner: owner,
    unavailableKey: 'menu.overlay.window.fleetUnavailable',
    build: (context, content) => ClassicFontScope(
      child: OfficialFleetPage(
        module: content.module,
        sharedShipsPort: content.sharedShips,
        hangarSharingPort: content.hangarSharing,
      ),
    ),
  );
}
