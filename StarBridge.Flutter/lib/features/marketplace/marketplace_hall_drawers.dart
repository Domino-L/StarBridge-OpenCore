import 'dart:async';

import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_action_row.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_banner.dart' show MarketplaceSurfaceColors;
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_details.dart';
import 'marketplace_hall_mine.dart' show marketSideColor;
import 'marketplace_hover.dart';
import 'marketplace_port.dart';
import 'marketplace_publish_entry.dart';
import 'marketplace_quality_copy.dart';
import 'marketplace_quality_widgets.dart' show MarketTierLadder;
import 'marketplace_trade_confirm.dart';
import 'marketplace_trade_copy.dart' show tradeItemName;
import 'marketplace_widgets.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

// Hover drawer contents (方案 E). Each builder only reads data the hall has
// already loaded; actions use [host], the page's own context, because the
// drawer itself closes before the action runs.

Widget _gap() => const SizedBox(height: 2);

String _percent(num value) =>
    '${value > 0 ? '+' : value < 0 ? '−' : ''}${value.abs().toStringAsFixed(1)}%';

/// Price against the live best, trade hours, location, age + 购买 / 出售给他.
Widget marketListingDrawer(
  BuildContext context,
  BuildContext host,
  MarketplaceController c,
  MarketRow row, {
  num? best,
  String? location,
}) {
  final t = context.tokens;
  final barter = row['displayType'] == 3;
  final buy = row['creatorType'] == 0;
  final price = marketNumber(row['unitPrice']);
  final itemId = marketItemId(row);
  final open = marketTradeOpenNow(row);
  final mine = marketIsMine(row);
  Widget? compare;
  if (!barter && best != null && best > 0 && price != null) {
    final leading = buy ? price >= best : price <= best;
    compare = MarketDrawerRow(
      marketText(context, buy ? 'drawerVsHighest' : 'drawerVsLowest'),
      leading
          ? marketText(context, buy ? 'drawerIsHighest' : 'drawerIsLowest')
          : _percent((price - best) / best * 100),
      color: leading ? t.colors.success : MarketplaceSurfaceColors.gold,
      mono: !leading,
    );
  }
  final window = marketTradeTime(context, row);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ?compare,
      MarketDrawerRow(
        marketText(context, 'drawerWindow'),
        Text.rich(
          TextSpan(
            children: [
              if (open != null)
                TextSpan(
                  text:
                      '● ${marketText(context, open ? 'tradeOpenNow' : 'tradeClosedNow')}  ',
                  style: TextStyle(
                    color: open ? t.colors.success : MarketplaceSurfaceColors.gold,
                  ),
                ),
              TextSpan(text: window),
            ],
          ),
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: t.colors.textPrimary),
        ),
      ),
      MarketDrawerRow(
        marketText(context, 'drawerPlace'),
        location == null || location.isEmpty ? marketLocation(context, row) : location,
      ),
      MarketDrawerRow(
        marketText(context, 'drawerListed'),
        MarketPublished(row['createTime']),
      ),
      _gap(),
      MarketDrawerActions([
        if (c.trades.supported && !barter && !mine)
          MarketSlantButton(
            marketText(context, buy ? 'drawerSellTo' : 'drawerBuy'),
            key: const ValueKey('drawer-trade'),
            filled: true,
            color: marketSideColor(context, buy ? 'buy' : 'sell'),
            onTap: () => unawaited(confirmMarketTrade(host, c, row)),
          ),
        if (itemId != null)
          MarketSlantButton(
            marketText(context, 'drawerItem'),
            onTap: () => c.openItem(itemId),
          ),
      ]),
    ],
  );
}

Widget _followButton(BuildContext context, BuildContext host, MarketplaceController c, int id) =>
    MarketSlantButton(
      marketText(context, c.favorites.contains(id) ? 'unfollow' : 'follow'),
      onTap: c.savingPreferences || c.preferencesFailed
          ? null
          : () async {
              await c.toggleFavorite(id);
              if (host.mounted && c.favoriteLimitReached) {
                ScaffoldMessenger.maybeOf(host)?.showOnly(
                  starBridgeTimedSnackBar(content: Text(marketText(host, 'watchLimit'))),
                );
              }
            },
    );

/// Trending: live lowest ask, highest bid and listing count, read when the
/// box opens (SCM's trending figures are 60-day averages and a count of
/// price records, user question 2026-10-23); quality items show the tier
/// ladder instead of one lowest ask. The average stays, labelled as one.
Widget marketTrendingDrawer(
  BuildContext context,
  BuildContext host,
  MarketplaceController c,
  MarketRow row,
) => ListenableBuilder(
  listenable: c,
  builder: (context, _) => _trendingDrawer(context, host, c, row),
);

Widget _trendingDrawer(
  BuildContext context,
  BuildContext host,
  MarketplaceController c,
  MarketRow row,
) {
  final t = context.tokens;
  final id = marketItemId(row);
  final change = marketNumber(row['changePercent']);
  final tiers = id == null ? null : c.qualityTiers.of(id);
  if (id != null && c.qualityTiers.stale(id)) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(c.qualityTiers.ensure(id)),
    );
  }
  final pending = tiers == null && id != null && c.qualityTiers.loading(id);
  String live(num? v) => pending
      ? marketText(context, 'loading')
      : v == null
      ? marketText(context, 'drawerNone')
      : marketMoney(v);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (tiers?.hasQuality == true) ...[
        MarketTierLadder(tiers!),
        const SizedBox(height: 4),
      ] else
        MarketDrawerRow(
          marketText(context, 'lowest'),
          live(tiers?.sellLowest),
          mono: true,
        ),
      MarketDrawerRow(
        marketText(context, 'highest'),
        live(tiers?.buyHighest),
        mono: true,
      ),
      if (tiers?.sellCount case final int count)
        MarketDrawerRow(
          marketText(context, 'drawerOnSale'),
          marketMoney(count),
          mono: true,
        ),
      if (marketNumber(row['price']) != null)
        MarketDrawerRow(
          qualityText(context, 'recentAverage'),
          marketMoney(row['price']),
          mono: true,
          color: t.colors.textSecondary,
        ),
      if (change != null)
        MarketDrawerRow(
          marketText(context, 'drawerChange'),
          _percent(change),
          mono: true,
          color: change == 0
              ? t.colors.textSecondary
              : change > 0
              ? t.colors.success
              : t.colors.danger,
        ),
      _gap(),
      if (id != null)
        MarketDrawerActions([
          MarketSlantButton(
            marketText(context, 'drawerQuotes'),
            filled: true,
            onTap: () => c.openItem(id),
          ),
          _followButton(context, host, c, id),
        ]),
    ],
  );
}

/// Catalogue item: sell / buy / checklist counts + quotes and follow.
Widget marketCatalogDrawer(
  BuildContext context,
  BuildContext host,
  MarketplaceController c,
  MarketRow row,
) {
  final id = marketItemId(row);
  String count(Object? v) => marketNumber(v) == null ? '—' : marketMoney(v);
  final checklist =
      (marketNumber(row['checklistSellCount']) ?? 0) +
      (marketNumber(row['checklistBuyCount']) ?? 0);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      MarketDrawerRow(marketText(context, 'sell'), count(row['sellOrderCount']), mono: true),
      MarketDrawerRow(marketText(context, 'buy'), count(row['buyOrderCount']), mono: true),
      if (row.containsKey('checklistSellCount') || row.containsKey('checklistBuyCount'))
        MarketDrawerRow(marketText(context, 'drawerChecklist'), marketMoney(checklist), mono: true),
      _gap(),
      if (id != null)
        MarketDrawerActions([
          MarketSlantButton(
            marketText(context, 'drawerQuotes'),
            filled: true,
            onTap: () => c.openItem(id),
          ),
          _followButton(context, host, c, id),
        ]),
    ],
  );
}

/// Category tile: its subcategories, each opening the market filtered to it.
Widget marketCategoryDrawer(
  BuildContext context,
  MarketplaceController c,
  int category,
) {
  final t = context.tokens;
  final children = [
    for (final row in c.blocks['categories']?.rows ?? const <MarketRow>[])
      if (marketNumber(row['parentId'])?.toInt() == category) row,
  ];
  if (children.isEmpty) return Text(marketText(context, 'drawerNoSub'));
  return Wrap(
    spacing: 12,
    runSpacing: 2,
    children: [
      for (final row in children)
        StarBridgeActionRow(
          inheritContentStyle: true,
          baseRadius: 2,
          onActivate: (_, _) {
            final id = marketNumber(row['id'])?.toInt();
            if (id != null) unawaited(c.browse(category: id));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              marketName(row, marketLocale(context), field: 'name'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.colors.textPrimary,
              ),
            ),
          ),
        ),
    ],
  );
}

String _expiry(Object? value) {
  final n = marketNumber(value);
  DateTime? at;
  if (n != null) {
    at = DateTime.fromMillisecondsSinceEpoch(n.toInt()).toLocal();
  } else if (value is String) {
    at = DateTime.tryParse(value)?.toLocal();
  }
  if (at == null) return value?.toString() ?? '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
}

/// My listing: expiry, active trades + 改价 / 下架(上架) / 复制.
Widget marketMineDrawer(
  BuildContext context,
  BuildContext host,
  MarketplaceController c,
  MarketRow row,
) {
  final visible = row['visible'] == true;
  final ongoing = row['hasOngoingTransactions'] == true;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (row['expiry'] != null)
        MarketDrawerRow(marketText(context, 'drawerExpiry'), _expiry(row['expiry'])),
      MarketDrawerRow(
        marketText(context, 'drawerOngoing'),
        marketText(context, ongoing ? 'drawerYes' : 'drawerNo'),
        color: ongoing ? MarketplaceSurfaceColors.gold : null,
      ),
      _gap(),
      MarketDrawerActions([
        MarketSlantButton(
          marketText(context, 'drawerEdit'),
          key: const ValueKey('drawer-edit'),
          filled: true,
          color: marketSideColor(context, row['side']?.toString()),
          onTap: () => unawaited(openMarketListingAction(host, c, row, 'edit')),
        ),
        MarketSlantButton(
          marketText(context, visible ? 'drawerHide' : 'drawerShow'),
          key: const ValueKey('drawer-visibility'),
          onTap: () => unawaited(openMarketListingAction(host, c, row, 'visibility')),
        ),
        MarketSlantButton(
          marketText(context, 'drawerCopy'),
          onTap: () => unawaited(openMarketListingAction(host, c, row, 'copy')),
        ),
      ]),
    ],
  );
}

/// 发布挂单: listing quota and the trade window from the trade profile.
Widget marketPublishDrawer(BuildContext context, MarketplaceController c) {
  final profile = c.tradeProfile;
  final live = c.myListings.where((r) => r['visible'] == true && r['checklist'] != true).length;
  final lists = c.myListings.where((r) => r['checklist'] == true).length;
  final limit = marketNumber(profile?['orderLimit'])?.toInt();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      MarketDrawerRow(
        marketText(context, 'drawerSingle'),
        limit == null ? '$live' : '$live / $limit',
        mono: true,
      ),
      MarketDrawerRow(marketText(context, 'drawerChecklists'), '$lists / 5', mono: true),
      if (profile != null)
        MarketDrawerRow(marketText(context, 'drawerWindow'), marketTradeTime(context, profile)),
    ],
  );
}

/// 我的交易: needs-action and active counts plus the most recent trade.
Widget marketTradesDrawer(BuildContext context, MarketplaceController c) {
  final t = context.tokens;
  final latest = c.trades.rows.isEmpty ? null : c.trades.rows.first;
  String state(MarketRow r) => switch (r['transactionStatus']) {
    2 => marketText(context, 'drawerDone'),
    1 => marketText(context, 'drawerActive'),
    _ => marketText(context, 'drawerCancelled'),
  };
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      MarketDrawerRow(
        marketText(context, 'drawerTodo'),
        '${c.trades.todo.length}',
        mono: true,
        color: c.trades.todo.isEmpty ? null : MarketplaceSurfaceColors.gold,
      ),
      MarketDrawerRow(marketText(context, 'drawerActive'), '${c.activeTradeCount}', mono: true),
      if (latest != null)
        MarketDrawerRow(
          marketText(context, 'drawerLatest'),
          '${tradeItemName(context, latest)} · ${state(latest)}',
          color: t.colors.textPrimary,
        ),
    ],
  );
}
