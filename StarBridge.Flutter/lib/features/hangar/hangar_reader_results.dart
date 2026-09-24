import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../ships/ship_display_names.dart';
import 'hangar_reader_copy.dart';
import 'hangar_arrival_timeline.dart';
import 'hangar_ship_icon.dart';
import 'hangar_combat_motion.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../shared/ships/ship_reviewed_display.dart';
import '../../shared/ships/ship_category_colors.dart';
import 'local_hangar_copy.dart';

/// Verified page results only; these rows are not a saved personal inventory.
class HangarReaderResults extends StatefulWidget {
  const HangarReaderResults({
    required this.view,
    required this.complete,
    this.arrivals,
    super.key,
  });
  final Map<String, Object?> view;
  final bool complete;
  final HangarArrivalTimeline? arrivals;
  @override
  State<HangarReaderResults> createState() => _HangarReaderResultsState();
}

class _HangarReaderResultsState extends State<HangarReaderResults> {
  final _localArrivals = HangarArrivalTimeline();

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final complete = widget.complete;
    final arrivals = widget.arrivals ?? _localArrivals;
    if (widget.arrivals == null) arrivals.accept(view);
    final copy = HangarReaderCopy(context);
    final tokens = context.tokens;
    final ships = (view['ships'] as List? ?? const []).cast<Map>();
    final count = view['shipCount'] as int? ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaces.panel.fill,
        border: Border.all(color: tokens.surfaces.panel.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        complete ? copy.preview : copy.detectedShips,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      copy.count(count),
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: tokens.colors.accent),
                    ),
                  ],
                ),
                if (!complete) ...[
                  const SizedBox(height: 4),
                  Text(
                    copy.liveResultsHint,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ],
                if (count > 200)
                  Text(
                    copy.previewLimit,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ships.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        copy.awaitingShips,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: tokens.colors.textSecondary),
                      ),
                    ),
                  )
                : ListView.separated(
                    key: Key(
                      complete
                          ? 'hangar-reader-preview'
                          : 'hangar-reader-live-list',
                    ),
                    primary: false,
                    itemCount: ships.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final ship = ships[index];
                      final rowId = HangarArrivalTimeline.rowId(ship, index);
                      final combatSize = HangarCombatSize.parse(
                        ship['combatSize'],
                      );
                      final original = ship['title'] as String? ?? '';
                      final display = ShipReviewedDisplay.parse(
                        ship['display'],
                      );
                      final metadata = LocalHangarCopy(context);
                      final liner = ship['liner'] as String? ?? '';
                      final names = ship['names'] is Map
                          ? ship['names'] as Map
                          : const {};
                      final title = ShipDisplayNames.primary(
                        Localizations.localeOf(context),
                        original: original,
                        simplifiedChinese: names['zhHans'] as String?,
                        traditionalChinese: names['zhHant'] as String?,
                      );
                      return ListTile(
                        key: ValueKey('${view['operationId']}:$rowId'),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${index + 1}'.padLeft(2, '0'),
                                style: TextStyle(
                                  color: tokens.colors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            HangarShipIcon(
                              key: ValueKey(
                                'combat:${view['operationId']}:$rowId',
                              ),
                              display: display,
                              legacyCombatSize: combatSize,
                              elapsed: arrivals.elapsed(rowId),
                              active: arrivals.active,
                              fallback: StarBridgeIcon(
                                StarBridgeIconSemantic.hangar,
                                size: 24,
                                color: tokens.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          title,
                          key: Key('hangar-reader-ship-name-$index'),
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title == original
                                  ? liner
                                  : [
                                      original,
                                      if (liner.isNotEmpty) liner,
                                    ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (display != null)
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (metadata.combatSize(display.spec)
                                      case final String size)
                                    Text(
                                      size,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  Text(
                                    metadata.category(display.role),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: shipCategoryColor(
                                            context,
                                            display.role,
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
