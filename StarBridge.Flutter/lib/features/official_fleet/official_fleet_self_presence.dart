import 'official_fleet_members_models.dart';

/// Current local presentation, never a publication or an audience grant.
final class OfficialFleetSelfPresence {
  const OfficialFleetSelfPresence({required this.key, this.sharingAllowed});
  final String key;
  // null means local consent/receipt is not known: retain the Host projection.
  final bool? sharingAllowed;

  OfficialFleetMember project(OfficialFleetMember member) {
    if (!member.isSelf ||
        member.identityState != OfficialFleetMemberIdentityState.starBridge ||
        member.starBridgeConnected != true) {
      return member;
    }
    if (sharingAllowed == false ||
        key == 'presence.invisible' ||
        key == 'presence.offline') {
      return member.withPresence(OfficialFleetMemberPresence.offline);
    }
    if (sharingAllowed != true || member.sharingPaused) return member;
    final presence = switch (key) {
      'presence.online' => OfficialFleetMemberPresence.online,
      'presence.away' => OfficialFleetMemberPresence.away,
      'presence.inGame' => OfficialFleetMemberPresence.inGame,
      _ => null,
    };
    return presence == null ? member : member.withPresence(presence);
  }
}
