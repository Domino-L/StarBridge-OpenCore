import '../../platform/bridge/bridge_client_session.dart';
import '../account/account_models.dart';
import '../onboarding/connection_mode_port.dart';
import '../common/organization_communication_bridge.dart';
import '../common/organization_communication_port.dart';

OrganizationCommunicationPort createOfficialFleetCommunicationAdapter(
  BridgeClientSession session,
  String sourceRef, {
  ConnectionModeControl? connectionMode,
  AccountProfile? Function()? ownProfile,
}) {
  if (!RegExp(r'^officialFleet:[1-9][0-9]{0,18}$').hasMatch(sourceRef)) {
    throw const FormatException();
  }
  return ScopedOrganizationCommunicationBridge(
    session,
    sourceRef,
    command: 'officialFleet.communication',
    connectionMode: connectionMode,
    ownAvatar: () => ownProfile?.call()?.avatarImageData,
    ownName: () => ownProfile?.call()?.displayName,
  );
}
