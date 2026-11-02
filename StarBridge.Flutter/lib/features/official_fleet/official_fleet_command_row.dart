import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_member_row.dart';
import 'official_fleet_member_views.dart';
import 'official_fleet_members_models.dart';
import 'official_fleet_rally.dart';
import 'official_fleet_rally_views.dart';

/// The command row under the holo header (user decision 2026-10-22): who is
/// online now, where the fleet is, and the owner's actions. It only appears
/// when the roster carries realtime presence; a running rally replaces it
/// with the rally strip.
class OfficialFleetCommandRow extends StatelessWidget {
  const OfficialFleetCommandRow({
    required this.members,
    required this.rally,
    this.sourceRef,
    this.onAnnounce,
    super.key,
  });

  final OfficialFleetMemberDirectoryProjection members;
  final OfficialFleetRallyController rally;
  final String? sourceRef;
  final VoidCallback? onAnnounce;

  static const _shown = 6;

  /// Presence rows are useful even when schema 2 omits aggregate counts.
  static bool available(OfficialFleetMemberDirectoryProjection members) =>
      members.availability ==
          OfficialFleetMemberDirectoryAvailability.available &&
      members.runtimeCapabilities.presence;

  /// The row also stays through a failed read, so the page below does not move.
  static bool holdsPlace(OfficialFleetMemberDirectoryProjection members) =>
      available(members) || members.presenceHeld;

  static bool _online(OfficialFleetMember member) => const {
    OfficialFleetMemberPresence.online,
    OfficialFleetMemberPresence.inGame,
  }.contains(member.publicPresence);

  /// The most shared location among in-game members who share it. Names are
  /// the roster's own display names; nothing beyond what the rows show.
  static String feed(
    AppStrings strings,
    OfficialFleetMemberDirectoryProjection members,
  ) {
    final groups = <String, List<OfficialFleetMember>>{};
    for (final member in members.members) {
      final location = member.publicLocation;
      if (member.publicPresence != OfficialFleetMemberPresence.inGame ||
          location.state != OfficialFleetMemberFieldState.value ||
          location.value == null ||
          member.identityState == OfficialFleetMemberIdentityState.restricted) {
        continue;
      }
      groups.putIfAbsent(location.value!, () => []).add(member);
    }
    if (groups.isEmpty) {
      final inGame = members.visibleInGameCount ?? 0;
      return inGame > 0
          ? strings
                .text('officialFleet.command.feed.inGame')
                .replaceAll('{count}', '$inGame')
          : strings.text('officialFleet.command.feed.none');
    }
    final top = groups.entries.reduce(
      (a, b) => b.value.length > a.value.length ? b : a,
    );
    final names = top.value.map((m) => m.callsign).toList();
    final key = switch (names.length) {
      1 => 'officialFleet.command.feed.one',
      2 => 'officialFleet.command.feed.two',
      _ => 'officialFleet.command.feed.many',
    };
    return strings
        .text(key)
        .replaceAll('{a}', names.first)
        .replaceAll('{b}', names.length > 1 ? names[1] : '')
        .replaceAll('{count}', '${names.length}')
        .replaceAll('{location}', top.key);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: rally,
    builder: (context, _) {
      if (!holdsPlace(members) ||
          rally.current?.activeAt(rally.now()) == true) {
        return const SizedBox.shrink();
      }
      final strings = AppStrings.of(context), tokens = context.tokens;
      final text = Theme.of(context).textTheme;
      final online = members.members.where(_online).toList();
      final shown = online.take(_shown).toList();
      final total = members.visibleOnlineCount;
      final rest = (total ?? online.length) - shown.length;
      final muted = text.labelMedium?.copyWith(
        color: tokens.colors.textSecondary,
        letterSpacing: .5,
      );
      return Container(
        key: const Key('official-fleet-command-row'),
        margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: tokens.colors.textSecondary.withValues(alpha: .25),
            ),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(height: 28),
            Text(strings.text('officialFleet.command.online'), style: muted),
            const SizedBox(width: 10),
            // Avatars keep their own shape and are never overlapped or cut
            // (user decision 2026-10-22).
            for (final (index, member) in shown.indexed)
              Padding(
                padding: EdgeInsets.only(left: index == 0 ? 0 : 4),
                child: Tooltip(
                  message: member.callsign,
                  child: SizedBox.square(
                    dimension: 28,
                    child: _avatar(
                      context,
                      member,
                      sourceRef: sourceRef,
                      allowProfile: false,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Text(
              members.presenceHeld
                  ? strings.text('officialFleet.command.unavailable')
                  : total == null
                  ? strings.text('officialFleet.members.enterAll')
                  : shown.isEmpty
                  ? strings
                        .text('officialFleet.command.count')
                        .replaceAll('{count}', '$total')
                  : rest > 0
                  ? strings
                        .text('officialFleet.command.more')
                        .replaceAll('{count}', '$rest')
                  : '',
              key: const Key('official-fleet-command-online-count'),
              style: muted,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                feed(strings, members),
                key: const Key('official-fleet-command-feed'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
            ),
            OfficialFleetRallyStartButton(controller: rally),
            if (onAnnounce != null)
              StarBridgeActionButton(
                controlKey: const Key('official-fleet-command-announce'),
                onActivate: (_) => onAnnounce!(),
                child: Text(strings.text('officialFleet.command.announce')),
              ),
          ],
        ),
      );
    },
  );
}

Widget _avatar(
  BuildContext context,
  OfficialFleetMember member, {
  String? sourceRef,
  bool allowProfile = true,
}) {
  final identity = officialFleetMemberEntry(
    context,
    member,
    sourceRef: sourceRef,
    allowProfile: allowProfile,
  ).identity;
  return identity is OrganizationMemberIdentity
      ? identity.avatar
      : const SizedBox.shrink();
}
