import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/embedded_avatar.dart';
import '../../shared/remote_image.dart';
import '../common/organization_member_copy.dart';
import '../common/organization_member_row.dart';
import '../common/user_avatar_menu.dart';
import '../common/organization_member_runtime.dart';
import '../party_rooms/room_display.dart' show roomServerRegion;
import 'official_fleet_members_models.dart';

/// Fleet authority stays in its projection; geometry and interaction belong to
/// the same member board used by community organizations and menu surfaces.
OrganizationMemberEntry officialFleetMemberEntry(
  BuildContext context,
  OfficialFleetMember member, {
  String? sourceRef,
  bool allowProfile = true,
}) {
  final tokens = context.tokens;
  final restricted =
      member.identityState == OfficialFleetMemberIdentityState.restricted;
  final linked =
      member.identityState == OfficialFleetMemberIdentityState.starBridge;
  final name = restricted
      ? AppStrings.of(context).text('officialFleet.members.identity.restricted')
      : member.callsign;
  final target =
      linked &&
          allowProfile &&
          sourceRef != null &&
          RegExp(r'^officialFleet:[1-9][0-9]*$').hasMatch(sourceRef) &&
          member.profileTargetRef == member.memberRef &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(member.memberRef)
      ? UserTarget(
          'officialFleet',
          member.profileTargetRef!,
          contextRef: sourceRef,
        )
      : null;
  final fallback = ColoredBox(
    color: tokens.surfaces.selected.fill,
    child: Center(
      child: restricted
          ? const StandardIcon(StandardIconSemantic.person)
          : Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
    ),
  );
  final avatar = linked
      ? EmbeddedAvatar(source: member.avatarImageData, fallback: fallback)
      : restricted || member.avatarUrl == null
      ? fallback
      : RemoteImage(
          member.avatarUrl!,
          kind: RemoteImageResourceKind.avatar,
          // RSI avatars only; a redirect could lead off the RSI host the Host
          // validated, so it is not followed.
          followRedirects: false,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        );
  final role = [
    if (member.officialRankName?.trim().isNotEmpty ?? false)
      member.officialRankName!.trim(),
    if (member.officialRankValue case final int rank
        when rank >= 1 && rank <= 5)
      '$rank★',
  ].join(' · ');
  return OrganizationMemberEntry(
    reference: member.memberRef,
    identity: OrganizationMemberIdentity(
      name: name,
      gameId: restricted ? '' : member.gameId,
      avatar: avatar,
      isSelf: linked && member.isSelf,
      target: target,
      includeSocialActions: false,
      avatarImageData: linked ? member.avatarImageData : null,
    ),
    role: role.isEmpty ? memberBoardText(context, 'unknown') : role,
    presence: switch (member.publicPresence) {
      OfficialFleetMemberPresence.online => OrganizationMemberPresence.online,
      OfficialFleetMemberPresence.away => OrganizationMemberPresence.away,
      OfficialFleetMemberPresence.inGame => OrganizationMemberPresence.inGame,
      OfficialFleetMemberPresence.offline ||
      OfficialFleetMemberPresence.invisible =>
        OrganizationMemberPresence.offline,
      _ => OrganizationMemberPresence.unknown,
    },
    runtime: officialFleetMemberRuntimeCells(context, member),
  );
}

MemberRuntimeCells officialFleetMemberRuntimeCells(
  BuildContext context,
  OfficialFleetMember member,
) {
  String? runtime(OfficialFleetMemberField field) => switch (field.state) {
    OfficialFleetMemberFieldState.notShared ||
    OfficialFleetMemberFieldState.restricted => null,
    OfficialFleetMemberFieldState.value => field.value,
    _ => 'Unknown',
  };
  final server = runtime(member.publicServer);
  return organizationMemberRuntimeCells(
    OrganizationMemberRuntimeFacts(
      publicInGame: member.publicPresence == OfficialFleetMemberPresence.inGame,
      serverRegion: server == null ? null : member.serverRegion,
      hasServerSession: server == null ? null : member.hasServerSession,
      ship: runtime(member.publicShip),
      location: runtime(member.publicLocation),
      locationHiddenReason: member.locationHiddenReason,
      arrivalPendingConfirmation: member.publicArrivalPending,
      arrivalTargetCode: member.publicArrivalPending
          ? member.arrivalTargetCode
          : null,
    ),
    text: (key) => memberBoardText(context, key),
    regionText: (region) => roomServerRegion(context, region),
    locale: AppStrings.of(context).locale,
  );
}

/// Compatibility facade for existing callers; there is no fleet-specific row
/// layout and no whole-row action. Width is handled by the shared row itself.
class OfficialFleetMemberRow extends StatelessWidget {
  const OfficialFleetMemberRow({
    required this.member,
    required this.wide,
    required this.onOpen,
    this.sourceRef,
    this.allowProfile = true,
    this.columns = const OrganizationMemberColumns.all(),
    super.key,
  });
  final OfficialFleetMember member;
  final bool wide;
  final VoidCallback onOpen;
  final String? sourceRef;
  final bool allowProfile;
  final OrganizationMemberColumns columns;

  @override
  Widget build(BuildContext context) => OrganizationMemberRow(
    entry: officialFleetMemberEntry(
      context,
      member,
      sourceRef: sourceRef,
      allowProfile: allowProfile,
    ),
    columns: columns,
    roleLabel: memberBoardText(context, 'rank'),
  );
}
