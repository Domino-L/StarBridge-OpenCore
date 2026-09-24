import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_ships_models.dart';

class OfficialFleetShipSummary extends StatelessWidget {
  const OfficialFleetShipSummary({required this.projection, super.key});

  final OfficialFleetShipsProjection projection;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: const Key('official-fleet-ships-summary'),
      role: SurfaceRole.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: tokens.space.sm,
            runSpacing: tokens.space.sm,
            children: [
              _SummaryMetric(
                labelKey: 'officialFleet.ships.metric.total',
                value: '${projection.totalCount ?? 0}',
                color: tokens.domainColors.ship.foreground,
              ),
              _SummaryMetric(
                labelKey: 'officialFleet.ships.metric.requestable',
                value: '${projection.requestableCount ?? 0}',
                color: tokens.colors.success,
              ),
              _SummaryMetric(
                labelKey: 'officialFleet.ships.metric.owners',
                value: '${projection.ownerCount ?? 0}',
                color: tokens.domainColors.logistics.foreground,
              ),
              _SummaryMetric(
                labelKey: 'officialFleet.ships.metric.value',
                value: '\$${projection.totalValueUsd ?? 0}',
                color: tokens.colors.info,
              ),
            ],
          ),
          SizedBox(height: tokens.space.md),
          Text(
            strings.text('officialFleet.ships.distribution.title'),
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.sm),
          _ShipSizeDistribution(
            counts: projection.sizeCounts,
            total: projection.totalCount ?? 0,
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.labelKey,
    required this.value,
    required this.color,
  });

  final String labelKey;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: 190,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.md,
        vertical: tokens.space.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaces.panel.fill,
        border: BorderDirectional(
          start: BorderSide(color: color, width: tokens.stroke.strong),
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppStrings.of(context).text(labelKey),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ),
          SizedBox(width: tokens.space.sm),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ShipSizeDistribution extends StatelessWidget {
  const _ShipSizeDistribution({required this.counts, required this.total});

  final Map<OfficialFleetShipSize, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final visible = OfficialFleetShipSize.values
        .where((size) => (counts[size] ?? 0) > 0)
        .toList(growable: false);
    final semanticLabel = visible
        .map(
          (size) =>
              '${AppStrings.of(context).text(_sizeLabelKey(size))} ${counts[size]}',
        )
        .join('，');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: semanticLabel,
          child: ClipRRect(
            borderRadius: tokens.shape.small,
            child: SizedBox(
              key: const Key('official-fleet-ships-size-distribution'),
              height: 12,
              child: total <= 0
                  ? ColoredBox(color: tokens.surfaces.panel.border)
                  : Row(
                      children: [
                        for (final size in visible)
                          Expanded(
                            flex: counts[size]!,
                            child: ColoredBox(color: _sizeColor(context, size)),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        SizedBox(height: tokens.space.sm),
        Wrap(
          spacing: tokens.space.md,
          runSpacing: tokens.space.xs,
          children: [
            for (final size in visible)
              _DistributionLegend(
                size: size,
                count: counts[size]!,
                color: _sizeColor(context, size),
              ),
          ],
        ),
      ],
    );
  }
}

class _DistributionLegend extends StatelessWidget {
  const _DistributionLegend({
    required this.size,
    required this.count,
    required this.color,
  });

  final OfficialFleetShipSize size;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: context.tokens.space.xs),
        Text('${AppStrings.of(context).text(_sizeLabelKey(size))} $count'),
      ],
    );
  }
}

Color _sizeColor(BuildContext context, OfficialFleetShipSize size) {
  final tokens = context.tokens;
  return switch (size) {
    OfficialFleetShipSize.capital => tokens.domainColors.command.foreground,
    OfficialFleetShipSize.large => tokens.domainColors.airCombat.foreground,
    OfficialFleetShipSize.medium => tokens.domainColors.ship.foreground,
    OfficialFleetShipSize.small => tokens.domainColors.logistics.foreground,
    OfficialFleetShipSize.unknown => tokens.colors.textSecondary,
  };
}

String _sizeLabelKey(OfficialFleetShipSize size) => switch (size) {
  OfficialFleetShipSize.capital => 'officialFleet.ships.size.capital',
  OfficialFleetShipSize.large => 'officialFleet.ships.size.large',
  OfficialFleetShipSize.medium => 'officialFleet.ships.size.medium',
  OfficialFleetShipSize.small => 'officialFleet.ships.size.small',
  OfficialFleetShipSize.unknown => 'officialFleet.ships.size.unknown',
};
