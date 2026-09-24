import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/ship_catalog_display.dart';
import 'community_ship_distribution_chart.dart';
import 'community_ship_statistics.dart';
import 'community_ships_copy.dart';

class CommunityFleetStatisticsDialog extends StatelessWidget {
  const CommunityFleetStatisticsDialog({required this.statistics, super.key});
  final CommunityShipStatistics statistics;
  @override
  Widget build(BuildContext context) {
    final stats = statistics;
    final colors = context.tokens.colors;
    final text = Theme.of(context).textTheme;
    String t(String key) => communityShipsText(context, key);
    Widget metric(String label, String value, {bool price = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: text.headlineSmall?.copyWith(
            fontSize: price ? 20 : 28,
            fontWeight: FontWeight.w700,
            color: price && stats.pricedCount == 0
                ? colors.textSecondary
                : colors.info,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          t(label),
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
    return Dialog(
      key: const ValueKey('community-statistics-dialog'),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: MediaQuery.sizeOf(context).height - 32,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('fleetSummary'), style: text.titleLarge),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final metrics = [
                            metric('count', '${stats.ships.length}'),
                            metric('modelCount', '${stats.modelCount}'),
                            metric(
                              'sharingMembers',
                              '${stats.sharingMemberCount}',
                            ),
                            metric(
                              'totalValue',
                              stats.pricedCount == 0
                                  ? t('noPriceData')
                                  : ShipCatalogDisplay.usd(stats.totalCents),
                              price: true,
                            ),
                          ];
                          return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              for (final item in metrics)
                                SizedBox(
                                  width:
                                      (constraints.maxWidth -
                                          (constraints.maxWidth >= 640
                                              ? 48
                                              : 16)) /
                                      (constraints.maxWidth >= 640 ? 4 : 2),
                                  child: item,
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${t('pricedCoverage')} ${stats.pricedCount} / ${stats.ships.length} · ${t('knownValueHint')}',
                        style: text.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const Divider(height: 28),
                      CommunityShipDistributionChart(statistics: stats),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('close')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
