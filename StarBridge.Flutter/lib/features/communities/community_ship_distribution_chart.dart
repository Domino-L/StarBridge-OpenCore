import '../../shared/ships/ship_category_colors.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_ship_statistics.dart';
import 'community_ships_copy.dart';

/// Two independent dimensions, one count scale. Loaners never enter the matrix.
class CommunityShipDistributionChart extends StatefulWidget {
  const CommunityShipDistributionChart({required this.statistics, super.key});
  final CommunityShipStatistics statistics;
  @override
  State<CommunityShipDistributionChart> createState() => _ChartState();
}

class _ChartState extends State<CommunityShipDistributionChart> {
  (String, String)? selected;
  @override
  void didUpdateWidget(covariant CommunityShipDistributionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statistics != widget.statistics) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.statistics;
    final colors = context.tokens.colors;
    final domains = context.tokens.domainColors;
    final palette = {
      'combat': domains.airCombat.foreground,
      'transport': domains.logistics.foreground,
      'industrial': domains.industry.foreground,
      'exploration': domains.recon.foreground,
      'support': domains.medical.foreground,
      'utility': colors.textSecondary,
      for (final role in CommunityShipStatistics.roleOrder)
        role: shipCategoryColor(context, role),
      'unknown': colors.textPrimary,
    };
    String t(String key) => communityShipsText(context, key);
    final sizes = CommunityShipStatistics.sizeOrder
        .where(
          (s) => s.startsWith('ground-') || s == 'unknown'
              ? stats.sizes.containsKey(s)
              : true,
        )
        .toList();
    final roles = CommunityShipStatistics.roleOrder
        .where(stats.roles.containsKey)
        .toList();
    final maximum = stats.sizes.values.fold(0, (a, b) => a > b ? a : b);
    String detail(String size, String role) {
      final count = stats.countAt(size, role);
      final subtotal = stats.sizes[size] ?? 0;
      String percent(int total) =>
          total == 0 ? '0%' : '${(count * 100 / total).toStringAsFixed(1)}%';
      return '${t(size)} · ${t(role)} · $count ${t('shipsUnit')} · ${t('ofSize')} ${percent(subtotal)} · ${t('ofFleet')} ${percent(stats.ships.length)}';
    }

    if (stats.ships.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(t('noSharedShips')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t('crossDistribution'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          t('crossHint'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final role in roles)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 9, height: 9, color: palette[role]),
                  const SizedBox(width: 6),
                  Text(
                    '${t(role)} ${stats.roles[role]}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final size in sizes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text(
                    t(size),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: ColoredBox(
                      color: colors.textSecondary.withValues(alpha: .05),
                      child: Row(
                        children: [
                          for (final role in roles)
                            if (stats.countAt(size, role) > 0)
                              Expanded(
                                flex: stats.countAt(size, role),
                                child: Tooltip(
                                  message: detail(size, role),
                                  child: Semantics(
                                    label: detail(size, role),
                                    button: true,
                                    child: InkWell(
                                      key: ValueKey(
                                        'ship-distribution-$size-$role',
                                      ),
                                      onTap: () => setState(
                                        () => selected = (size, role),
                                      ),
                                      onFocusChange: (focus) {
                                        if (focus) {
                                          setState(
                                            () => selected = (size, role),
                                          );
                                        }
                                      },
                                      onHover: (hover) {
                                        if (hover) {
                                          setState(
                                            () => selected = (size, role),
                                          );
                                        }
                                      },
                                      child: Ink(
                                        color: palette[role]!.withValues(
                                          alpha: .55,
                                        ),
                                        child: LayoutBuilder(
                                          builder: (context, constraints) => Center(
                                            child: constraints.maxWidth >= 30
                                                ? ExcludeSemantics(
                                                    child: Text(
                                                      '${stats.countAt(size, role)}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: colors
                                                                .textPrimary,
                                                          ),
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          if (maximum > (stats.sizes[size] ?? 0))
                            Expanded(
                              flex: maximum - (stats.sizes[size] ?? 0),
                              child: const SizedBox(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${stats.sizes[size] ?? 0}',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 78, end: 44),
          child: Row(
            children: [
              Text('0', style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text(
                '$maximum ${t('shipsUnit')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Text(
              selected == null
                  ? t('chartHint')
                  : detail(selected!.$1, selected!.$2),
              key: const ValueKey('ship-distribution-selection'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        ExpansionTile(
          key: const ValueKey('ship-distribution-table-toggle'),
          tilePadding: EdgeInsets.zero,
          title: Text(
            t('crossTable'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const ValueKey('ship-distribution-table'),
                horizontalMargin: 8,
                columnSpacing: 24,
                columns: [
                  DataColumn(label: Text(t('spec'))),
                  for (final role in roles)
                    DataColumn(label: Text(t(role)), numeric: true),
                  DataColumn(label: Text(t('total')), numeric: true),
                ],
                rows: [
                  for (final size in sizes)
                    DataRow(
                      cells: [
                        DataCell(Text(t(size))),
                        for (final role in roles)
                          DataCell(Text('${stats.countAt(size, role)}')),
                        DataCell(Text('${stats.sizes[size] ?? 0}')),
                      ],
                    ),
                  DataRow(
                    cells: [
                      DataCell(Text(t('total'))),
                      for (final role in roles)
                        DataCell(Text('${stats.roles[role]}')),
                      DataCell(Text('${stats.ships.length}')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
