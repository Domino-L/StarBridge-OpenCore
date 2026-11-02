import 'package:flutter/material.dart';

import '../../design_system/icons/native_dropdown_indicator_icon.dart';

import '../../design_system/interaction/starbridge_expansion_tile.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_summary.dart';

class LocalHangarOverview extends StatelessWidget {
  const LocalHangarOverview({required this.ships, super.key});
  final List<LocalHangarPresentation> ships;
  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), t = context.tokens;
    final totals = LocalHangarTotals(ships);
    final value =
        '${totals.unpricedCount > 0 ? c.knownValue : c.valueLabel} · '
        '${totals.pricedCount == 0 ? '—' : c.usd(totals.knownValueUsd)}';
    final statuses = [
      for (final status in ['flyable', 'concept'])
        if ((totals.statuses[status] ?? 0) > 0)
          '${c.status(status)} ${totals.statuses[status]}',
    ];
    return Material(
      color: Colors.transparent,
      // The expander owns the only focus/activation target. Keep the passive
      // price-basis hint outside its non-interactive rich header, so that it
      // remains available rather than being swallowed by the header's guards.
      child: StarBridgeTooltip(
        message: c.priceBasis,
        excludeFromSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: StarBridgeExpansionTile(
            key: const Key('local-hangar-summary'),
            useNativePageStorage: true,
            headerMinHeight: 0,
            title:
                '${c.shipsLabel} ${totals.count}, $value, ${c.priceBasis}, ${statuses.join(', ')}',
            headerBuilder: (context, visual, open) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Wrap(
                spacing: 20,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.shipsLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${totals.count}',
                        key: const Key('local-hangar-total-count'),
                      ),
                    ],
                  ),
                  Text(
                    value,
                    key: const Key('hangar-compact-value'),
                    style: TextStyle(color: t.colors.textSecondary),
                  ),
                  for (final status in statuses)
                    Text(status, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              trailing: Transform.rotate(
                angle: 3.141592653589793 * open,
                child: const NativeDropdownIndicatorIcon.expandMore(),
              ),
            ),
            children: [LocalHangarSummary(ships: ships, embedded: true)],
          ),
        ),
      ),
    );
  }
}
