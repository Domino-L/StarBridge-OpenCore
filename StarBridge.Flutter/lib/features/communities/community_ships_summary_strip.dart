import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'community_image_decoder.dart';
import 'community_ship_statistics.dart';
import 'community_ships_copy.dart';
import 'community_workspace_image.dart';

/// The ships page's one-line summary: the counts, the sharing members'
/// avatars, the known value and the way into the full statistics. The size
/// bar is gone (user 2026-10-30: unreadable, and the filter chips right below
/// already count each size). Its height is the same in every state, so
/// nothing below it moves when the statistics arrive; narrow windows scroll
/// it sideways.
class CommunityShipsSummaryStrip extends StatelessWidget {
  const CommunityShipsSummaryStrip({
    required this.statistics,
    required this.loading,
    required this.failed,
    required this.onRetry,
    required this.onDetails,
    this.avatarOf,
    this.decoder,
    super.key,
  });

  final CommunityShipStatistics? statistics;
  final bool loading, failed;
  final VoidCallback onRetry;
  final VoidCallback? onDetails;
  final Uint8List? Function(String memberRef)? avatarOf;
  final CommunityImageDecoder? decoder;

  static const height = 56.0;
  static const _gap = 26.0;

  @override
  Widget build(BuildContext context) {
    final stats = statistics;
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    String t(String key) => communityShipsText(context, key);
    final muted = text.bodySmall?.copyWith(color: tokens.colors.textSecondary);
    final dim = muted?.copyWith(
      color: tokens.colors.textSecondary.withValues(alpha: .7),
    );
    final border = BoxDecoration(
      border: Border(bottom: BorderSide(color: tokens.surfaces.panel.border)),
    );
    if (stats == null) {
      return Container(
        key: const ValueKey('community-ship-statistics'),
        height: height,
        decoration: border,
        child: Row(
          children: [
            Expanded(
              child: Text(
                t(failed ? 'statisticsUnavailable' : 'statisticsLoading'),
                style: muted,
              ),
            ),
            if (failed)
              StarBridgeActionButton(
                controlKey: const Key('community-ship-statistics-retry'),
                kind: StarBridgeActionKind.quiet,
                onActivate: (_) => onRetry(),
                child: Text(t('imageRetry')),
              ),
          ],
        ),
      );
    }
    Widget stat(String value, String label, {bool small = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: text.titleLarge?.copyWith(
            fontSize: small ? 16 : 22,
            fontWeight: FontWeight.w700,
            color: small ? tokens.colors.textSecondary : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: muted),
      ],
    );
    final avatars = <Widget>[];
    for (final owner in stats.owners.entries.take(5)) {
      final bytes = avatarOf?.call(owner.key);
      final name = CommunityShipStatistics.owner(owner.value.first);
      avatars.add(
        StarBridgeTooltip(
          message: name,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsetsDirectional.only(end: 2),
            decoration: BoxDecoration(
              color: tokens.surfaces.raised.fill,
              border: Border.all(color: tokens.surfaces.panel.border),
            ),
            child: bytes == null
                ? Center(
                    child: Text(
                      name.isEmpty ? '?' : name.characters.first,
                      style: text.labelSmall,
                    ),
                  )
                : CommunityWorkspaceImage(
                    bytes: bytes,
                    decoder: decoder ?? decodeCommunityImage,
                    maxWidth: 64,
                    icon: StandardIconSemantic.person,
                  ),
          ),
        ),
      );
    }
    final value = stats.pricedCount == 0
        ? null
        : ShipCatalogDisplay.usd(stats.totalCents);
    final leading = [
      stat('${stats.shipCount}', t('shipsUnit')),
      stat('${stats.modelCount}', t('modelCount')),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...avatars,
          const SizedBox(width: 10),
          stat('${stats.sharingMemberCount}', t('membersSharing'), small: true),
        ],
      ),
    ];
    final trailing = [
      Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          stat(value ?? '—', t('totalValue'), small: true),
          Text(
            '${t('pricedCoverage')} ${stats.pricedCount} / ${stats.shipCount}',
            style: dim?.copyWith(fontSize: 11),
          ),
        ],
      ),
      StarBridgeActionButton(
        controlKey: const ValueKey('community-ship-statistics-expand'),
        kind: StarBridgeActionKind.quiet,
        onActivate: onDetails == null ? null : (_) => onDetails!(),
        child: Text(t('viewStatistics')),
      ),
    ];
    List<Widget> spaced(List<Widget> items) => [
      for (var index = 0; index < items.length; index++) ...[
        if (index > 0) const SizedBox(width: _gap),
        items[index],
      ],
    ];
    return Container(
      key: const ValueKey('community-ship-statistics'),
      height: height,
      decoration: border,
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 1100
            ? Row(
                children: [
                  ...spaced(leading),
                  const Spacer(),
                  ...spaced(trailing),
                ],
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: spaced([...leading, ...trailing])),
              ),
      ),
    );
  }
}
