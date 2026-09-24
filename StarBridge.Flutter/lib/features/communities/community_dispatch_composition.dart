import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/catalog_vehicle_icon.dart';
import 'community_ship_statistics.dart';
import 'community_ships_port.dart';
import 'community_ships_copy.dart';

/// The bar counts shared instances; category counts describe actual candidates.
/// These two denominators deliberately remain separate when loaners exist.
class CommunityDispatchComposition extends StatelessWidget {
  const CommunityDispatchComposition({required this.statistics, super.key});
  final CommunityShipStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final stats = statistics;
    final colors = context.tokens.colors;
    final text = Theme.of(context).textTheme.bodySmall;
    String t(String key) => communityShipsText(context, key);
    final total = stats.ships.length;
    final statuses = [
      ('dispatchable', stats.available.length, colors.success),
      ('ownerOffline', stats.ownerOffline, colors.offline),
      ('pendingAvailability', stats.availabilityUnknown, colors.warning),
      ('notFlyable', stats.notFlyable, colors.danger),
    ];
    final groups = <(String, String), List<CommunitySharedShip>>{};
    for (final ship in stats.candidates) {
      groups
          .putIfAbsent((
            CommunityShipStatistics.size(ship),
            CommunityShipStatistics.role(ship),
          ), () => [])
          .add(ship);
    }
    final share = total == 0
        ? '—'
        : '${(stats.available.length * 100 / total).toStringAsFixed(0)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: t('dispatchScope'),
          child: Text(
            '${t('availabilityShare')}  ${stats.available.length} / $total ${t('shipsUnit')} · $share',
            key: const ValueKey('community-dispatch-share'),
            style: text?.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: statuses.map((s) => '${t(s.$1)} ${s.$2}').join(', '),
          child: SizedBox(
            height: 6,
            child: total == 0
                ? ColoredBox(color: colors.textDisabled.withValues(alpha: .2))
                : Row(
                    children: [
                      for (final status in statuses)
                        if (status.$2 > 0)
                          Expanded(
                            flex: status.$2,
                            child: Tooltip(
                              message:
                                  '${t(status.$1)} ${status.$2} ${t('shipsUnit')}',
                              excludeFromSemantics: true,
                              child: ColoredBox(
                                key: ValueKey('dispatch-segment-${status.$1}'),
                                color: status.$3,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Tooltip(
          message: stats.hasDispatchLoaners
              ? t('dispatchCandidateHint')
              : t('dispatchScope'),
          child: Text(
            t(
              stats.hasDispatchLoaners
                  ? 'dispatchTypesLoaners'
                  : 'dispatchTypes',
            ),
            style: text?.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: 4),
        if (groups.isEmpty)
          Text(t('noneDispatchable'), style: text)
        else
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final size in CommunityShipStatistics.sizeOrder)
                for (final role in CommunityShipStatistics.roleOrder)
                  if (groups[(size, role)] case final ships?)
                    _DispatchTypeGroup(size: size, role: role, ships: ships),
            ],
          ),
      ],
    );
  }
}

class _DispatchTypeGroup extends StatelessWidget {
  const _DispatchTypeGroup({
    required this.size,
    required this.role,
    required this.ships,
  });
  final String size, role;
  final List<CommunitySharedShip> ships;

  @override
  Widget build(BuildContext context) {
    // Artwork encodes BOTH size and a precise catalog category. Broad role
    // names cannot choose a representative icon: racing/ground variants may
    // share a broad role. Require every candidate to agree on an exact key.
    final key = ships.first.displayIcon;
    final match = RegExp(
      r'^(combat|exploration|logistics|industrial|support|competition|unclassified)-(small|medium|large|capital)$',
    ).firstMatch(key ?? '');
    final reviewed = ships.every((ship) => ship.display != null);
    final showIcon =
        key != null &&
        ships.every((ship) => ship.displayIcon == key) &&
        (reviewed ||
            match != null &&
                match[2] == size &&
                !(match[1] == 'competition' && size == 'capital'));
    String t(String value) => communityShipsText(context, value);
    return Row(
      key: ValueKey('dispatch-category-$size-$role'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) ...[
          CatalogVehicleIcon.byKey(iconKey: key, size: 24),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            '${t(size)} · ${t(role)} ${ships.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
