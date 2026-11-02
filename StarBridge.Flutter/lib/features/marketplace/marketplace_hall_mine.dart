import 'dart:async';

import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_action_row.dart';

import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_diagonal.dart';
import 'marketplace_hall_drawers.dart';
import 'marketplace_hover.dart';
import 'marketplace_port.dart';
import 'marketplace_publish_entry.dart';
import 'marketplace_widgets.dart';

const _gold = MarketplacePalette.gold;

Color marketSideColor(BuildContext context, String? side) => switch (side) {
  'buy' => MarketplacePalette.buyer,
  'barter' => _gold,
  _ => context.tokens.colors.accent,
};

/// The hall's always-present 我的挂单: live listings first, hidden ones on a
/// hatched ground, and a publish cell when there is room. Each card says
/// whether the price is currently the best on SCM.
class MarketMyListingsStrip extends StatefulWidget {
  const MarketMyListingsStrip(this.c, {super.key});
  final MarketplaceController c;
  @override
  State<MarketMyListingsStrip> createState() => _StripState();
}

class _StripState extends State<MarketMyListingsStrip> {
  MarketplaceController get c => widget.c;

  List<MarketRow> get _rows => [
    ...c.myListings.where((r) => r['visible'] == true),
    ...c.myListings.where((r) => r['visible'] != true),
  ];

  void _askBestPrices(List<MarketRow> rows) {
    final wanted = [
      for (final r in rows)
        if (marketNumber(r['itemId']) != null && r['side'] != 'barter')
          (marketNumber(r['itemId'])!.toInt(), r['side'] == 'buy' ? 0 : 1),
    ];
    if (wanted.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(c.ensureBestPrices(wanted));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!c.myListingsLoaded) {
      return const SizedBox(height: 2, child: LinearProgressIndicator());
    }
    final rows = _rows;
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 900 ? 4 : 2;
        final cells = columns * 2;
        final shown = rows.length <= cells - 1 ? rows : rows.take(cells - 1).toList();
        _askBestPrices(shown);
        final children = <Widget>[
          for (final r in shown) _MineCard(c, r),
          rows.length <= cells - 1
              ? _CellButton(
                  label: '＋ ${marketText(context, 'publishListing')}',
                  onTap: () => openMarketPublish(context, c),
                  hatch: true,
                )
              : _CellButton(
                  label: marketTextN(context, 'mineAll', rows.length),
                  onTap: c.openMyListings,
                ),
        ];
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: (box.maxWidth / columns - 10) / 86,
          children: children,
        );
      },
    );
  }
}

class _MineCard extends StatelessWidget {
  const _MineCard(this.c, this.row);
  final MarketplaceController c;
  final MarketRow row;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = row['side']?.toString();
    final color = marketSideColor(context, side);
    final hidden = row['visible'] != true;
    final itemId = marketNumber(row['itemId'])?.toInt();
    final price = marketNumber(row['price']);
    final buy = side == 'buy';
    final best = itemId == null || side == 'barter' ? null : c.bestPrice(itemId, buy ? 0 : 1);
    final known = itemId != null && side != 'barter' && c.hasBestPrice(itemId, buy ? 0 : 1);
    Widget? hint;
    if (hidden) {
      hint = Text(marketText(context, 'listingHidden'), style: TextStyle(color: t.colors.textSecondary));
    } else if (known && price != null && best != null) {
      final leading = buy ? price >= best : price <= best;
      hint = leading
          ? Text('● ${marketText(context, buy ? 'mineTopBid' : 'mineLowest')}', style: TextStyle(color: t.colors.success))
          : Text(
              '▲ ${marketTextN(context, buy ? 'mineOutbid' : 'mineUndercut', marketMoney(best))}',
              style: const TextStyle(color: _gold),
            );
    }
    return MarketHoverCard(
      color: color,
      drawerKey: const ValueKey('market-drawer'),
      drawer: (drawer) => marketMineDrawer(drawer, context, c, row),
      child: Material(
      color: Colors.transparent,
      child: StarBridgeActionRow(
        inheritContentStyle: true,
        hoverFace: false,
        baseRadius: 0,
        onActivate: itemId == null ? null : (_, _) => c.openItem(itemId),
        child: CustomPaint(
          painter: hidden ? MarketHatchPainter(t.colors.textSecondary.withValues(alpha: .07)) : null,
          child: Container(
            decoration: BoxDecoration(
              gradient: hidden
                  ? null
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [t.surfaces.raised.fill, t.surfaces.panel.fill],
                    ),
              border: Border(
                left: BorderSide(color: color, width: 3),
                top: BorderSide(color: t.surfaces.panel.border),
                right: BorderSide(color: t.surfaces.panel.border),
                bottom: BorderSide(color: t.surfaces.panel.border),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(9, 9, 12, 9),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 64,
                  child: MarketArt(
                    marketIsChecklist(row) ? marketChecklistArt : row['image']?.toString(),
                    category: marketCategoryOf(row),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Opacity(
                    opacity: hidden ? .6 : 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['name'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        MarketVerbPrice(side: side, price: price, quantity: row['quantity'], compact: true),
                        if (hint != null) ...[
                          const SizedBox(height: 3),
                          DefaultTextStyle.merge(
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            child: hint,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _CellButton extends StatelessWidget {
  const _CellButton({required this.label, required this.onTap, this.hatch = false});
  final String label;
  final VoidCallback onTap;
  final bool hatch;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MarketHoverCard(
      child: Material(
        color: Colors.transparent,
        child: StarBridgeActionRow(
          inheritContentStyle: true,
          hoverFace: false,
          baseRadius: 0,
          onActivate: (_, _) => onTap(),
          child: CustomPaint(
            painter: hatch ? MarketHatchPainter(t.colors.accent.withValues(alpha: .08)) : null,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border.all(color: t.surfaces.panel.border)),
              child: Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.colors.accent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "出售 ¤100,000 ×8": the direction verb in its colour, gold money, quantity.
class MarketVerbPrice extends StatelessWidget {
  const MarketVerbPrice({
    required this.side,
    required this.price,
    this.quantity,
    this.compact = false,
    super.key,
  });
  final String? side;
  final Object? price, quantity;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final verb = marketText(context, switch (side) {
      'buy' => 'verbBuy',
      'barter' => 'verbSwap',
      _ => 'verbSell',
    });
    return Row(
      // Hugs its content so a right-aligned column lines up under its header.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          verb,
          style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w600, color: marketSideColor(context, side)),
        ),
        const SizedBox(width: 5),
        if (marketNumber(price) != null)
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '¤ ',
                    style: TextStyle(fontSize: compact ? 12 : 14, color: _gold.withValues(alpha: .8)),
                  ),
                  TextSpan(text: marketPrice(context, price)),
                ],
              ),
              semanticsLabel: '¤ ${marketMoney(price)}',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontFamily: t.typography.monoFamily,
                fontSize: compact ? 15 : 18,
                fontWeight: FontWeight.w600,
                color: _gold,
              ),
            ),
          ),
        if (quantity != null) ...[
          const SizedBox(width: 6),
          Text(
            '×$quantity',
            style: TextStyle(fontSize: compact ? 11 : 12, color: t.colors.textSecondary),
          ),
        ],
      ],
    );
  }
}
