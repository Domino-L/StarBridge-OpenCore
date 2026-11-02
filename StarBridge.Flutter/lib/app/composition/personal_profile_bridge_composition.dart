import '../../features/hangar/bridge_local_hangar.dart';
import '../../features/personal_profile/bridge_local_personal_profile.dart';
import '../../features/personal_profile/bridge_personal_profile_adapter.dart';
import '../../features/personal_profile/personal_profile_port.dart';
import '../../platform/bridge/bridge_client_session.dart';

/// Main and menu profiles retain the same local/remote owners and their own
/// read lifetimes; only the static inventory measurement origin differs.
PersonalProfilePort createBridgePersonalProfilePort(
  BridgeClientSession session, {
  required HangarReadOrigin inventoryOrigin,
}) => BridgeLocalPersonalProfile(
  session,
  remote: BridgePersonalProfileAdapter(session),
  hangar: () => BridgeLocalHangar(session, readOrigin: inventoryOrigin),
);
