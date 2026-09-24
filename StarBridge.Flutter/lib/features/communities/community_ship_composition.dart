import '../../shared/ships/ship_category_colors.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_ship_statistics.dart';
import 'community_ships_copy.dart';

/// Counts and lengths share one authorized full-inventory denominator.
class CommunityShipComposition extends StatelessWidget {
  const CommunityShipComposition({required this.statistics, super.key});
  final CommunityShipStatistics statistics;
  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final domains = context.tokens.domainColors;
    final sizes = {
      'capital': domains.command.foreground,
      'large': colors.info,
      'medium': colors.warning,
      'small': colors.success,
      'ground-large': colors.info,
      'ground-medium': colors.warning,
      'ground-small': colors.success,
      'unknown': colors.textSecondary,
    };
    final roles = {
      'combat': domains.airCombat.foreground,
      'transport': domains.logistics.foreground,
      'industrial': domains.industry.foreground,
      'exploration': domains.recon.foreground,
      'support': domains.medical.foreground,
      'utility': colors.textSecondary,
      for (final role in CommunityShipStatistics.roleOrder)
        role: shipCategoryColor(context, role),
      'unknown': colors.textSecondary,
    };
    Widget legend(
      Map<String, Color> palette,
      Map<String, int> counts,
    ) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in palette.entries)
            if ((counts[entry.key] ?? 0) > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 14),
                child: Text(
                  '${communityShipsText(context, entry.key)} ${counts[entry.key]}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: entry.value),
                ),
              ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        legend(sizes, statistics.sizes),
        const SizedBox(height: 5),
        ExcludeSemantics(
          child: SizedBox(
            height: 4,
            child: Row(
              children: [
                for (final entry in sizes.entries)
                  if ((statistics.sizes[entry.key] ?? 0) > 0)
                    Expanded(
                      flex: statistics.sizes[entry.key]!,
                      child: ColoredBox(
                        color: entry.value,
                        child: const SizedBox.expand(),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        legend(roles, statistics.roles),
      ],
    );
  }
}
