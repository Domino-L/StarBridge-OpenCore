import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo_art.dart';
import '../common/organization_holo_deck.dart';
import 'official_fleet_models.dart';
import 'official_fleet_overview_models.dart';
import 'official_fleet_members_models.dart';

/// The main fleet's deck for the shared holo header and bar: RSI banner and
/// logo, SID, the viewer's official position, the current announcement and
/// the official, online and in-game counts.
OrganizationHoloDeck officialFleetHoloDeck(
  BuildContext context, {
  required OfficialFleetSummary fleet,
  required OfficialFleetOverviewProjection overview,
  OfficialFleetMemberDirectoryProjection? members,
  Widget? announcementEntry,
}) {
  final strings = AppStrings.of(context);
  final available =
      overview.availability == OfficialFleetOverviewAvailability.available;
  final metrics = available ? overview.metrics : null;
  return OrganizationHoloDeck(
    name: fleet.name,
    code: fleet.sid,
    banner: OrganizationHoloArt.fromUrl(fleet.profile?.bannerUrl),
    logo: OrganizationHoloArt.fromUrl(fleet.displayLogoUrl),
    tag:
        '${strings.text('officialFleet.myOfficialPosition')} · '
        '${fleet.officialRankName ?? strings.text('officialFleet.rank.unknown')} · '
        '${fleet.officialRankValue == null ? '—' : '${fleet.officialRankValue}★'}',
    // Before fleet reads are enabled there is no announcement source: the
    // line is left out rather than reading "unavailable" under the name.
    line: announcementEntry != null
        ? (_) => announcementEntry
        : !available
        ? null
        : (narrow) => Text(
            overview.announcement?.title ??
                strings.text('officialFleet.overview.announcement.none'),
            key: const Key('official-fleet-current-announcement'),
            maxLines: narrow ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.tokens.colors.textPrimary),
          ),
    stats: [
      for (final (key, value) in [
        ('members', metrics?.officialMemberCount ?? fleet.profile?.memberCount),
        (
          'online',
          members == null
              ? metrics?.visibleOnlineCount
              : members.visibleOnlineCount,
        ),
        (
          'inGame',
          members == null
              ? metrics?.visibleInGameCount
              : members.visibleInGameCount,
        ),
      ])
        if (value != null || key != 'members' && members?.presenceHeld == true)
          OrganizationHoloStat(
            strings.text('officialFleet.overview.metric.$key'),
            value,
            accent: key == 'online',
          ),
    ],
  );
}
