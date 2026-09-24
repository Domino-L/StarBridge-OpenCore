import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'community_ship_statistics.dart';
import 'community_fleet_statistics_dialog.dart';
import 'community_ship_composition.dart';
import 'community_dispatch_composition.dart';
import 'community_ships_copy.dart';

/// Inventory facts and present availability are separate read-only surfaces.
/// Both use the same complete, authorized inventory snapshot.
class CommunityShipStatisticsView extends StatelessWidget {
  const CommunityShipStatisticsView({
    required this.statistics,
    required this.onDetails,
    super.key,
  });
  final CommunityShipStatistics statistics;
  final void Function(bool dispatch) onDetails;

  @override
  Widget build(BuildContext context) {
    final stats = statistics;
    final colors = context.tokens.colors;
    String t(String key) => communityShipsText(context, key);
    Widget metric(
      String label,
      String value,
      Color color, {
      String? hint,
      bool quiet = false,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: hint ?? value,
          child: SizedBox(
            height: 30,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: quiet ? 14 : 24,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
        ),
        Tooltip(
          message: t(label),
          child: Text(
            t(label),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
    Widget card({
      required bool dispatch,
      required List<Widget> metrics,
      String? note,
      Widget? composition,
    }) => Container(
      constraints: const BoxConstraints(minHeight: 232),
      key: ValueKey(
        dispatch ? 'community-dispatch-summary' : 'community-fleet-summary',
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.tokens.surfaces.raised.fill,
        border: Border.all(color: context.tokens.surfaces.panel.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t(dispatch ? 'dispatchSummary' : 'fleetSummary'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                key: ValueKey(
                  dispatch
                      ? 'community-dispatch-details'
                      : 'community-ship-statistics-expand',
                ),
                onPressed: () => onDetails(dispatch),
                child: Text(t(dispatch ? 'viewDispatch' : 'viewDistribution')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final columns =
                  constraints.maxWidth >= metrics.length * 110 * scale
                  ? metrics.length
                  : 2;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  for (final item in metrics)
                    SizedBox(
                      width:
                          (constraints.maxWidth - (columns - 1) * 12) / columns,
                      child: item,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          if (note != null)
            Text(
              note,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          if (composition != null) ...[const SizedBox(height: 7), composition],
        ],
      ),
    );
    final summary = card(
      dispatch: false,
      metrics: [
        metric('count', '${stats.ships.length}', colors.info),
        metric('modelCount', '${stats.modelCount}', colors.textPrimary),
        metric(
          'sharingMembers',
          '${stats.sharingMemberCount}',
          colors.textPrimary,
        ),
        metric(
          'totalValue',
          stats.pricedCount == 0
              ? t('noPriceData')
              : ShipCatalogDisplay.usd(stats.totalCents),
          stats.pricedCount == 0 ? colors.textSecondary : colors.info,
          quiet: stats.pricedCount == 0,
        ),
      ],
      note:
          '${t('pricedCoverage')} ${stats.pricedCount} / ${stats.ships.length}',
      composition: CommunityShipComposition(statistics: stats),
    );
    final dispatch = card(
      dispatch: true,
      metrics: [
        metric('dispatchable', '${stats.available.length}', colors.success),
        metric(
          'ownerOffline',
          '${stats.ownerOffline}',
          colors.offline,
          hint: t('offlineShips'),
        ),
        metric(
          'pendingAvailability',
          '${stats.availabilityUnknown}',
          colors.warning,
        ),
        if (stats.notFlyable > 0)
          metric('notFlyable', '${stats.notFlyable}', colors.danger),
      ],
      composition: CommunityDispatchComposition(statistics: stats),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 760
          ? Row(
              key: const ValueKey('community-ship-statistics'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: summary),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: dispatch),
              ],
            )
          : Column(
              key: const ValueKey('community-ship-statistics'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, const SizedBox(height: 10), dispatch],
            ),
    );
  }
}

class CommunityShipStatisticsDetails extends StatelessWidget {
  const CommunityShipStatisticsDetails({
    required this.statistics,
    required this.dispatch,
    super.key,
  });
  final CommunityShipStatistics statistics;
  final bool dispatch;

  @override
  Widget build(BuildContext context) {
    if (!dispatch) {
      return CommunityFleetStatisticsDialog(statistics: statistics);
    }
    final stats = statistics;
    final colors = context.tokens.colors;
    String t(String key) => communityShipsText(context, key);
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SelectableText('${t(label)} · $value'),
    );
    final preferred = stats.preferred;
    return AlertDialog(
      key: const ValueKey('community-dispatch-dialog'),
      title: Text(t('dispatchSummary')),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('dispatchScope')),
              const SizedBox(height: 16),
              fact('dispatchable', '${stats.available.length}'),
              fact(
                'preferred',
                preferred == null
                    ? '—'
                    : '${preferred.displayName} · ${CommunityShipStatistics.owner(preferred)}',
              ),
              CommunityDispatchComposition(statistics: stats),
              if (stats.hasDispatchLoaners) ...[
                const SizedBox(height: 8),
                Text(t('dispatchCandidateHint')),
              ],
              const Divider(height: 24),
              if (stats.available.isEmpty) Text(t('noneDispatchable')),
              for (final owner in stats.owners.values)
                if (owner.any(stats.available.contains))
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(CommunityShipStatistics.owner(owner.first)),
                    trailing: Text(
                      '${owner.where(stats.available.contains).length}',
                    ),
                    children: [
                      for (final ship in owner.where(stats.available.contains))
                        ListTile(
                          dense: true,
                          title: Text(ship.displayName),
                          subtitle: Text(
                            CommunityShipStatistics.concept(ship)
                                ? '${t('loaners')} · ${ship.loaners!.where((item) => CommunityShipStatistics.flyable(item.forDispatch(ship))).map((item) => item.displayName.isEmpty ? item.code : item.displayName).join(' / ')}'
                                : communityShipDisplayText(context, ship.displayRole),
                          ),
                        ),
                    ],
                  ),
              const Divider(height: 24),
              fact('ownerOffline', '${stats.ownerOffline}'),
              fact('notFlyable', '${stats.notFlyable}'),
              if (stats.availabilityUnknown > 0)
                Text(
                  '${t('availabilityUnknown')} · ${stats.availabilityUnknown}',
                  style: TextStyle(color: colors.warning),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('close')),
        ),
      ],
    );
  }
}
