import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_member_row.dart';
import 'official_fleet_chat_tile.dart';
import 'official_fleet_command_row.dart';
import 'official_fleet_member_views.dart';
import 'official_fleet_members_models.dart';
import 'official_fleet_models.dart';
import 'official_fleet_module.dart' show OfficialFleetModule;
import 'official_fleet_overview_models.dart';
import 'official_fleet_rally.dart';
import 'official_fleet_section_rail.dart';
import '../common/organization_communication.dart';
import '../communities/community_settings_workspace.dart'
    show communitySettingsText;
import '../communities/community_ships_copy.dart' show communityShipsCulture;
import '../communities/community_ships_port.dart';
import '../communities/community_workspace_copy.dart' show workspaceText;
import 'official_fleet_ship_count.dart';

/// Whether the activity section has anything real to show this viewer.
bool officialFleetActivityAvailable(
  OrganizationCommunication communication,
  OfficialFleetRallyController rally,
) =>
    communication.announcementsAvailable ||
    rally.canStart ||
    rally.current?.activeAt(rally.now()) == true;

/// The RSI member count the bar shows: the overview's when available, else
/// the public profile's.
int? fleetRsiMemberCount(OfficialFleetModule module, OfficialFleetSummary fleet) {
  final overview = module.overview.projection.value;
  return overview.availability == OfficialFleetOverviewAvailability.available
      ? overview.metrics?.officialMemberCount ?? fleet.profile?.memberCount
      : fleet.profile?.memberCount;
}

/// Previews for the top screen's tall section tiles (user decision
/// 2026-10-22). Only data the page already holds; a section without any
/// gets a note instead (see [OfficialFleetRailItem.note]).
abstract final class OfficialFleetRailPreviews {
  /// Online avatars (own shape, never clipped) and the in-game split.
  static Widget? members(
    BuildContext context,
    OfficialFleetMemberDirectoryProjection members,
    OfficialFleetOverviewMetrics? metrics,
    String sourceRef,
  ) {
    if (!OfficialFleetCommandRow.available(members)) return null;
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final online = [
      for (final member in members.members)
        if (const {
          OfficialFleetMemberPresence.online,
          OfficialFleetMemberPresence.inGame,
        }.contains(member.publicPresence))
          member,
    ];
    final inGame = members.visibleInGameCount;
    final strings = AppStrings.of(context);
    return Column(
      key: const Key('official-fleet-tile-members'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // As many 24px avatars as the tile fits (at most 7), then +N.
        LayoutBuilder(
          builder: (context, box) {
            final fit = ((box.maxWidth - 36) / 28).floor().clamp(1, 7);
            final shown = online.take(fit).toList();
            final rest = online.length - shown.length;
            return Row(
              children: [
                for (final (index, member) in shown.indexed)
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: index == 0 ? 0 : 4,
                    ),
                    child: SizedBox.square(
                      dimension: 24,
                      child: switch (officialFleetMemberEntry(
                        context,
                        member,
                        sourceRef: sourceRef,
                        allowProfile: false,
                      ).identity) {
                        final OrganizationMemberIdentity identity =>
                          identity.avatar,
                        _ => const SizedBox.shrink(),
                      },
                    ),
                  ),
                if (rest > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '+$rest',
                    style: text.bodySmall?.copyWith(
                      color: tokens.colors.textDisabled,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        if (inGame != null) ...[
          const SizedBox(height: 8),
          Text(
            strings
                .text('officialFleet.tile.presence')
                .replaceAll('{inGame}', '$inGame')
                .replaceAll(
                  '{online}',
                  '${members.visibleOnlineCount! - inGame}',
                ),
            style: text.bodySmall?.copyWith(color: tokens.colors.textSecondary),
          ),
        ],
        if (inGame == null) ...[
          const SizedBox(height: 8),
          Text(
            strings.text('officialFleet.members.enterAll'),
            style: text.bodySmall?.copyWith(color: tokens.colors.textSecondary),
          ),
        ],
      ],
    );
  }

  /// What is new: a running rally, then the current announcement's title, two
  /// lines of its summary, time and author. Both open in the activity section.
  static Widget? activity(
    BuildContext context,
    OfficialFleetOverviewAnnouncement? announcement, {
    OfficialFleetRally? rally,
  }) {
    if (announcement == null && rally == null) return null;
    final tokens = context.tokens;
    final rallyLine = rally == null
        ? null
        : Text(
            rally.text,
            key: const Key('official-fleet-tile-rally'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.colors.warning,
            ),
          );
    if (announcement == null) return rallyLine;
    final text = Theme.of(context).textTheme;
    final at = announcement.publishedAtUtc.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return Column(
      key: const Key('official-fleet-tile-broadcast'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rallyLine != null) ...[rallyLine, const SizedBox(height: 8)],
        Text(
          announcement.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (announcement.summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            announcement.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: tokens.colors.textSecondary),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          '${two(at.month)}/${two(at.day)} ${two(at.hour)}:${two(at.minute)}'
          '${announcement.authorLabel.isEmpty ? '' : ' · ${announcement.authorLabel}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelSmall?.copyWith(
            fontFamily: tokens.typography.monoFamily,
            color: tokens.colors.textDisabled,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  /// The viewer's verified owner state, as on the settings page.
  static Widget? owner(BuildContext context, {required bool isOwner}) {
    if (!isOwner) return null;
    final tokens = context.tokens;
    final ok = tokens.colors.success;
    return Container(
      key: const Key('official-fleet-tile-owner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [ok.withValues(alpha: .12), ok.withValues(alpha: 0)],
        ),
        border: BorderDirectional(start: BorderSide(color: ok, width: 2)),
      ),
      child: Text(
        AppStrings.of(context).text('officialFleet.tile.ownerProof'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  /// The five rail entries of the upper screen, with their tile previews.
  static List<OfficialFleetRailItem> items(
    BuildContext context, {
    required OfficialFleetOverviewProjection overview,
    required OrganizationCommunication communication,
    required OfficialFleetMemberDirectoryProjection members,
    required String sourceRef,
    required bool isOwner,
    required OfficialFleetRallyController rally,
    required bool chatTileOnScreen,
    required OfficialFleetShipCount shipCount,
    required CommunityShipsPort? shipsPort,
  }) {
    final strings = AppStrings.of(context);
    String t(String key) => strings.text(key);
    final metrics = overview.metrics;
    final unread = communication.chatUnreadCount;
    final unavailable = t('officialFleet.workspace.unavailable');
    final recent = communication.chatRecent;
    final rallyLive = rally.current?.activeAt(rally.now()) == true
        ? rally.current
        : null;
    final owner = isOwner;
    if (TickerMode.valuesOf(context).enabled) {
      shipCount.load(
        shipsPort,
        communication.verifiedWorkspaceTargetRef,
        communityShipsCulture(context),
      );
    } else {
      shipCount.left();
    }
    final ships = shipCount.count ?? metrics?.sharedRequestableShipCount;
    return [
      OfficialFleetRailItem(
        section: OfficialFleetWorkspaceSection.members,
        label: t('officialFleet.tab.members'),
        summary: members.visibleOnlineCount == null
            ? ''
            : t('officialFleet.rail.members')
                  .replaceAll('{count}', '${members.totalCount}')
                  .replaceAll('{online}', '${members.visibleOnlineCount}'),
        preview: OfficialFleetRailPreviews.members(
          context,
          members,
          metrics,
          sourceRef,
        ),
        note: t('officialFleet.tile.membersNote'),
      ),
      OfficialFleetRailItem(
        section: OfficialFleetWorkspaceSection.channel,
        label: t('officialFleet.tab.channel'),
        summary: unread > 0
            ? t('officialFleet.rail.unread').replaceAll('{count}', '$unread')
            : t('officialFleet.rail.chat'),
        highlight: unread > 0,
        count: unread,
        // Nothing read yet, or no access: the plain note, never an error mark.
        previewFit: recent.isEmpty
            ? null
            : (height) => OfficialFleetChatTile(
                key: const Key('official-fleet-tile-chat'),
                communication: communication,
                unread: unread,
                height: height,
                onScreen: chatTileOnScreen,
              ),
        note: t('officialFleet.tile.chatNote'),
        enabled: communication.chatAvailable,
        hint: unavailable,
      ),
      OfficialFleetRailItem(
        section: OfficialFleetWorkspaceSection.ships,
        label: t('officialFleet.tab.ships'),
        // The same words as a community tile, in the same order.
        summary: ships == 0
            ? workspaceText(context, 'holo.shipsNone')
            : ships != null
            ? workspaceText(
                context,
                'holo.ships',
              ).replaceAll('{count}', '$ships')
            : shipCount.reading
            ? workspaceText(context, 'holo.shipsLoading')
            : shipCount.failed
            ? workspaceText(context, 'holo.shipsFailed')
            : t('officialFleet.rail.shipsNone'),
        note: t('officialFleet.tile.shipsNote'),
      ),
      OfficialFleetRailItem(
        section: OfficialFleetWorkspaceSection.broadcasts,
        label: t('officialFleet.tab.broadcasts'),
        // The header already shows the current title; no repeat here.
        summary: rallyLive != null
            ? t('officialFleet.rally.live')
            : overview.announcement == null
            ? t('officialFleet.rail.noAnnouncement')
            : t('officialFleet.rail.broadcasts'),
        highlight: rallyLive != null,
        preview: OfficialFleetRailPreviews.activity(
          context,
          overview.announcement,
          rally: rallyLive,
        ),
        note: t('officialFleet.tile.broadcastNote'),
        enabled: officialFleetActivityAvailable(communication, rally),
        hint: unavailable,
      ),
      OfficialFleetRailItem(
        section: OfficialFleetWorkspaceSection.manage,
        label: communitySettingsText(context, 'title'),
        preview: OfficialFleetRailPreviews.owner(context, isOwner: owner),
        note: t('officialFleet.tile.manageNote'),
        summary: owner
            ? t('officialFleet.rail.owner')
            : t('officialFleet.rail.settings'),
      ),
    ];
  }
}
