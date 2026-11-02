import 'package:flutter/material.dart';

import 'community_ships_port.dart';

typedef CommunityShipRowBuilder = Widget Function(
  CommunitySharedShip ship, {
  required bool card,
});

/// The card grid over every loaded page (user decision 2026-10-29, option D:
/// pages accumulate as the reader scrolls). [trailing] is the load-more row.
class CommunityShipsCardGrid extends StatelessWidget {
  const CommunityShipsCardGrid({
    required this.ships,
    required this.row,
    required this.listKey,
    this.controller,
    this.trailing,
    this.minColumnWidth = 280,
    super.key,
  });

  final List<CommunitySharedShip> ships;
  final CommunityShipRowBuilder row;
  final Key listKey;
  final ScrollController? controller;
  final Widget? trailing;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = ((constraints.maxWidth - 16) / minColumnWidth)
          .floor()
          .clamp(1, 6);
      final rows = (ships.length / columns).ceil();
      return ListView.separated(
        key: listKey,
        controller: controller,
        padding: const EdgeInsetsDirectional.only(end: 16),
        itemCount: rows + (trailing == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          if (index == rows) return trailing!;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 14),
                Expanded(
                  child: index * columns + column < ships.length
                      ? row(ships[index * columns + column], card: true)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          );
        },
      );
    },
  );
}

/// The aligned list over every loaded page.
class CommunityShipsListRows extends StatelessWidget {
  const CommunityShipsListRows({
    required this.ships,
    required this.row,
    required this.listKey,
    this.controller,
    this.trailing,
    super.key,
  });

  final List<CommunitySharedShip> ships;
  final CommunityShipRowBuilder row;
  final Key listKey;
  final ScrollController? controller;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListView.separated(
    key: listKey,
    controller: controller,
    padding: const EdgeInsetsDirectional.only(end: 16),
    itemCount: ships.length + (trailing == null ? 0 : 1),
    separatorBuilder: (_, _) => const SizedBox(height: 8),
    itemBuilder: (context, index) {
      if (index == ships.length) return trailing!;
      return row(ships[index], card: false);
    },
  );
}
