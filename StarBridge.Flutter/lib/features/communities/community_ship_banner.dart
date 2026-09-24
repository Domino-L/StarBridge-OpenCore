import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_ships_copy.dart';

/// WPF-style horizontal inventory entry; only compact windows wrap metadata.
class CommunityShipBanner extends StatelessWidget {
  const CommunityShipBanner({
    required this.identity,
    required this.spec,
    required this.status,
    required this.price,
    required this.role,
    required this.vehicleIcon,
    required this.owner,
    required this.importedAt,
    required this.action,
    super.key,
  });
  final Widget identity,
      spec,
      status,
      price,
      role,
      vehicleIcon,
      owner,
      importedAt,
      action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final classification = Row(
        key: const ValueKey('community-ship-classification'),
        mainAxisSize: MainAxisSize.min,
        children: [
          vehicleIcon,
          const SizedBox(width: 8),
          Flexible(child: spec),
          const SizedBox(width: 8),
          Flexible(child: role),
        ],
      );
      final cells = [
        identity,
        classification,
        status,
        price,
        owner,
        importedAt,
      ];
      if (constraints.maxWidth >= 900) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: CommunityShipColumns(cells: [...cells, action]),
        );
      }
      const labels = ['specRole', 'status', 'price', 'owner', 'importedAt'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              action,
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (var i = 1; i < cells.length; i++)
                SizedBox(
                  width: ((constraints.maxWidth - 16) / 2).clamp(0, 220),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        communityShipsText(context, labels[i - 1]),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.tokens.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      cells[i],
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}

/// Shared column geometry keeps headers and instances aligned on wide screens.
/// Classification, status and value stay together instead of stretching apart.
class CommunityShipColumns extends StatelessWidget {
  const CommunityShipColumns({required this.cells, super.key});
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final generous = constraints.maxWidth >= 1150;
      final widths = <int, double>{
        1: generous ? 220 : 176,
        2: generous ? 96 : 74,
        3: generous ? 112 : 82,
        5: generous ? 112 : 94,
        6: 72,
      };
      return Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            if (widths.containsKey(i))
              SizedBox(
                width: widths[i],
                child: Padding(
                  padding: EdgeInsetsDirectional.only(end: i == 6 ? 0 : 12),
                  child: cells[i],
                ),
              )
            else
              Expanded(
                flex: i == 0 ? 6 : 4,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 16),
                  child: cells[i],
                ),
              ),
        ],
      );
    },
  );
}

class CommunityShipColumnHeader extends StatelessWidget {
  const CommunityShipColumnHeader({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    // Same border/padding and scrollbar gutter as the inventory rows.
    padding: const EdgeInsetsDirectional.fromSTEB(13, 0, 29, 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) return const SizedBox.shrink();
        return CommunityShipColumns(
          cells: [
            for (final key in [
              'shipColumn',
              'specRole',
              'status',
              'priceColumn',
              'owner',
              'importedAt',
            ])
              Text(
                communityShipsText(context, key),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.tokens.colors.textSecondary),
              ),
            const SizedBox.shrink(),
          ],
        );
      },
    ),
  );
}
