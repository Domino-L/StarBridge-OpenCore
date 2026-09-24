import '../../shared/ships/ship_category_colors.dart';

import 'package:flutter/material.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_presentation.dart';

class LocalHangarSummary extends StatelessWidget {
  const LocalHangarSummary({required this.ships, super.key});
  final List<LocalHangarPresentation> ships;

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), tokens = context.tokens;
    final totals = LocalHangarTotals(ships);
    final colors = tokens.colors;
    final metrics = [
      _Metric(
        label: c.shipsLabel,
        value: '${totals.count}',
        color: tokens.domainColors.ship.foreground,
        valueKey: const Key('local-hangar-total-count'),
      ),
      _Metric(
        label: totals.unpricedCount > 0 ? c.knownValue : c.valueLabel,
        value: totals.pricedCount == 0 ? '—' : c.usd(totals.knownValueUsd),
        hint: totals.pricedCount == 0
            ? (totals.count == 0 ? c.priceBasis : c.noPrice)
            : c.priceBasis,
        secondaryHint: totals.unpricedCount > 0
            ? c.unpriced(totals.unpricedCount)
            : null,
        color: totals.pricedCount == 0 ? colors.textSecondary : colors.info,
        valueKey: const Key('local-hangar-total-value'),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.delivery, style: Theme.of(context).textTheme.labelMedium),
          SizedBox(height: tokens.space.sm),
          Wrap(
            spacing: tokens.space.md,
            runSpacing: tokens.space.xs,
            children: [
              for (final status in ['flyable', 'concept', 'unknown'])
                if ((totals.statuses[status] ?? 0) > 0)
                  _Legend(
                    label: '${c.status(status)} ${totals.statuses[status]}',
                    color: switch (status) {
                      'flyable' => colors.success,
                      'concept' => colors.warning,
                      _ => colors.textSecondary,
                    },
                  ),
              if (totals.count == 0) const Text('—'),
            ],
          ),
        ],
      ),
    ];
    return StarBridgeSurface(
      key: const Key('local-hangar-summary'),
      role: SurfaceRole.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(c.summary, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: tokens.space.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final columns = constraints.maxWidth >= 620 * scale
                  ? 3
                  : constraints.maxWidth >= 280 * scale
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - tokens.space.lg * (columns - 1)) /
                  columns;
              return Wrap(
                spacing: tokens.space.lg,
                runSpacing: tokens.space.md,
                children: [
                  for (var index = 0; index < metrics.length; index++)
                    SizedBox(
                      width: columns == 2 && index == 2
                          ? constraints.maxWidth
                          : width,
                      child: metrics[index],
                    ),
                ],
              );
            },
          ),
          if (totals.count > 0) ...[
            SizedBox(height: tokens.space.md),
            Divider(color: tokens.surfaces.raised.border, height: 1),
            SizedBox(height: tokens.space.md),
            Text(
              c.roleDistribution,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            SizedBox(height: tokens.space.sm),
            Semantics(
              label: LocalHangarPresentation.categories
                  .where((role) => (totals.roles[role] ?? 0) > 0)
                  .map((role) => '${c.category(role)} ${totals.roles[role]}')
                  .join(', '),
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: tokens.shape.small,
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        for (final role in LocalHangarPresentation.categories)
                          if ((totals.roles[role] ?? 0) > 0)
                            Expanded(
                              key: ValueKey('local-hangar-distribution-$role'),
                              flex: totals.roles[role]!,
                              child: ColoredBox(
                                color: hangarRoleColor(context, role),
                                child: const SizedBox.expand(),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: tokens.space.sm),
            Wrap(
              spacing: tokens.space.md,
              runSpacing: tokens.space.xs,
              children: [
                for (final role in LocalHangarPresentation.categories)
                  if ((totals.roles[role] ?? 0) > 0)
                    _Legend(
                      label:
                          '${c.category(role)} ${totals.roles[role]} · ${(totals.roles[role]! * 100 / totals.count).toStringAsFixed(0)}%',
                      color: hangarRoleColor(context, role),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
    required this.valueKey,
    this.hint,
    this.secondaryHint,
  });
  final String label, value;
  final String? hint, secondaryHint;
  final Color color;
  final Key valueKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      Text(
        value,
        key: valueKey,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      if (hint != null)
        Text(hint!, style: Theme.of(context).textTheme.bodySmall),
      if (secondaryHint != null)
        Text(secondaryHint!, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(child: Container(width: 6, height: 6, color: color)),
      const SizedBox(width: 6),
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

Color hangarRoleColor(BuildContext context, String role) {
  return shipCategoryColor(context, role);
}
