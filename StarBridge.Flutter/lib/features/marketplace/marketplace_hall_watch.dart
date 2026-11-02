import 'package:flutter/material.dart';

import '../../design_system/icons/favorite_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_hall_helpers.dart';
import 'marketplace_port.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_widgets.dart';

/// The hall's "我的关注" strip (G3, 0.7.2; preview watch-2): under 我的挂单,
/// changed items first, at most three, then "全部 N 件 →" to the 关注 tab.
class MarketHallWatch extends StatelessWidget {
  const MarketHallWatch(this.c, {super.key});
  final MarketplaceController c;

  @override
  Widget build(BuildContext context) {
    final entries = c.watchEntries;
    final order = {for (final (i, id) in c.favorites.indexed) id: i};
    entries.sort((a, b) {
      if (a.changed != b.changed) return a.changed ? -1 : 1;
      return order[a.id]!.compareTo(order[b.id]!);
    });
    final shown = entries.take(3).toList();
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 900 ? 4 : 2;
        final width = (box.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry in shown)
              SizedBox(width: width, child: _WatchTile(c, entry)),
            SizedBox(
              width: width,
              height: 76,
              child: MarketSurface(
                padding: EdgeInsets.zero,
                child: StarBridgeActionRow(
                  controlKey: const Key('market-hall-watch-all'),
                  inheritContentStyle: true,
                  baseRadius: 0,
                  onActivate: (_, _) => c.tab(5),
                  child: Center(
                    child: Text(
                      '${marketTextN(context, 'watchAll', c.favorites.length)} →',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: context.tokens.colors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WatchTile extends StatelessWidget {
  const _WatchTile(this.c, this.entry);
  final MarketplaceController c;
  final MarketWatchEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final item = entry.item;
    final change = entry.changePercent;
    final note = [
      if (change != null && change.abs() >= .05)
        '${change > 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(1)}%',
      if (entry.newListings > 0) '+${entry.newListings}',
    ].join('  ');
    // Two price lines (no ask, best bid) plus a change note may be taller
    // than the usual tile; grow rather than clip.
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      decoration: BoxDecoration(
        color: t.surfaces.panel.fill,
        border: Border(
          left: BorderSide(
            width: 3,
            color: entry.changed ? MarketplacePalette.gold : marketLine(context),
          ),
          top: BorderSide(color: marketLine(context)),
          right: BorderSide(color: marketLine(context)),
          bottom: BorderSide(color: marketLine(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: StarBridgeActionRow(
              controlKey: ValueKey(('market-watch-row', entry.id)),
              inheritContentStyle: true,
              baseRadius: 0,
              onActivate: (_, _) => c.openItem(entry.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 52,
                      child: item == null ? const MarketArt(null) : MarketArt.of(item),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item == null ? marketText(context, 'itemNameMissing') : marketName(item, marketLocale(context)),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          DefaultTextStyle.merge(
                            style: const TextStyle(fontSize: 12),
                            child: marketWatchPrice(context, c, entry.id),
                          ),
                          if (note.isNotEmpty)
                            Text(
                              note,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: (change ?? 0) < 0 ? t.colors.danger : t.colors.success,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          StarBridgeNativeIconAction(
            controlKey: ValueKey(('market-watch-favorite', entry.id)),
            style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
            label: marketText(context, 'favorites'),
            onActivate: c.savingPreferences || c.preferencesFailed
                ? null
                : (_) => c.toggleFavorite(entry.id),
            icon: const FavoriteIcon(selected: true, size: 16, color: MarketplacePalette.heart),
          ),
        ],
      ),
    );
  }
}
