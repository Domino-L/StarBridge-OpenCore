import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/styles/marketplace_palette.dart';
import 'marketplace_listing_copy.dart';
import 'package:flutter/material.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_port.dart';
import 'marketplace_states.dart' show marketButtonAction;
import '../../design_system/interaction/starbridge_action_row.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_unified.dart' show MarketSubTab, MarketSubTabs;

/// Compact segmented switch, same style as the trades page.
class ListingSegments<T> extends StatelessWidget {
  const ListingSegments({super.key, 
    required this.segments,
    required this.selected,
    required this.onSelected,
  });
  final Map<T, String> segments;
  final T selected;
  final ValueChanged<T> onSelected;
  @override
  // The hall's second-level tabs (G13, 0.7.2): the old boxed segments were
  // the last ones left after the page style unification.
  Widget build(BuildContext context) => MarketSubTabs([
    for (final e in segments.entries)
      MarketSubTab(
        e.value,
        selected: e.key == selected,
        onTap: () => onSelected(e.key),
        controlKey: ValueKey(('listing-segment', e.key)),
      ),
  ]);
}

class ListingCapacity extends StatelessWidget {
  const ListingCapacity({super.key, required this.used, required this.limit});
  final int used;
  final int? limit;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: listingText(context, 'capRule'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${listingText(context, '挂单')} '),
                TextSpan(
                  text: '$used',
                  style: TextStyle(
                    fontFamily: t.typography.monoFamily,
                    fontWeight: FontWeight.w600,
                    color: t.colors.textPrimary,
                  ),
                ),
                TextSpan(
                  text: ' / ${limit ?? '—'}',
                  style: TextStyle(fontFamily: t.typography.monoFamily),
                ),
              ],
            ),
            style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
          ),
          if (limit != null && limit! > 0) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (used / limit!).clamp(0, 1).toDouble(),
                  minHeight: 4,
                  backgroundColor: marketLine(context),
                  color: t.colors.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ListingBatchButton extends StatelessWidget {
  const ListingBatchButton(this.label, this.icon, this.onPressed, {super.key});
  final String label;
  final MarketplaceGlyph icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: marketButtonAction(OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onPressed,
      icon: MarketplaceIcon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    )),
  );
}

class ListingTag extends StatelessWidget {
  const ListingTag(this.text, this.color, {super.key});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    constraints: const BoxConstraints(minHeight: 20),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );
}

class ListingSideTag extends StatelessWidget {
  const ListingSideTag(this.side, {super.key});
  final String? side;
  @override
  Widget build(BuildContext context) => switch (side) {
    'sell' => ListingTag(listingText(context, '出售'), context.tokens.colors.accent),
    'buy' => ListingTag(listingText(context, '求购'), MarketplacePalette.buyer),
    'barter' => ListingTag(
      listingText(context, '以物易物'),
      context.tokens.colors.textSecondary,
    ),
    _ => const SizedBox.shrink(),
  };
}

class ListingPriceHint extends StatelessWidget {
  const ListingPriceHint({super.key, required this.optimal, required this.text, this.onEdit});
  final bool optimal;
  final String? text;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final color = optimal
        ? MarketplacePalette.success
        : MarketplacePalette.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MarketplaceIcon(
          optimal ? MarketplaceGlyph.confirmed : MarketplaceGlyph.warning,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 4),
        if (text != null)
          Flexible(
            child: Text(
              text!,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(fontSize: 11.5, color: color),
            ),
          ),
        if (!optimal)
          StarBridgeActionRow(
            inheritContentStyle: true,
            controlKey: const Key('market-listing-reprice'),
            baseRadius: 2,
            onActivate: onEdit == null ? null : (_, _) => onEdit!(),
            child: Text(
              listingText(context, '改价'),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.tokens.colors.accent,
              ),
            ),
          ),
      ],
    );
  }
}

class ListingListingStatus extends StatelessWidget {
  const ListingListingStatus(this.row, {super.key});
  final MarketRow row;
  @override
  Widget build(BuildContext context) {
    final expired = row['expired'] == true, visible = row['visible'] == true;
    final color = expired || !visible
        ? context.tokens.colors.textSecondary
        : MarketplacePalette.success;
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          expired
              ? listingText(context, '已过期')
              : visible
              ? listingText(context, '上架中')
              : listingText(context, '已下架'),
          style: TextStyle(fontSize: 11, color: color),
        ),
      ),
    );
  }
}

class ListingListHeader extends StatelessWidget {
  const ListingListHeader({super.key, required this.narrow});
  final bool narrow;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = TextStyle(
      fontFamily: t.typography.monoFamily,
      fontSize: 11,
      letterSpacing: .66,
      color: t.colors.textSecondary,
    );
    return Container(
      height: 34,
      color: Color.alphaBlend(
        t.surfaces.ground.fill.withValues(alpha: .3),
        t.surfaces.panel.fill,
      ),
      padding: const EdgeInsets.only(left: 13, right: 10),
      child: Row(
        children: [
          const SizedBox(width: 48 + 44 + 12),
          Expanded(
            flex: 4,
            child: Text(listingText(context, '物品'), style: style),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(listingText(context, '价格'), style: style),
          ),
          SizedBox(
            width: 40,
            child: Text(
              listingText(context, '数量'),
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: narrow ? 68 : 100,
            child: Text(listingText(context, '状态'), style: style),
          ),
          const SizedBox(width: 96),
        ],
      ),
    );
  }
}
