import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/favorite_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_diagonal.dart';
import 'marketplace_port.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_unified.dart';
import 'marketplace_widgets.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

const _copy = <String, List<String>>{
  'title': ['我的关注', '我的關注', 'Watching'],
  'summary': ['共 {n} 件', '共 {n} 件', '{n} items'],
  'changedN': ['{n} 件有变化', '{n} 件有變化', '{n} changed'],
  'local': ['只存在本机', '只存在本機', 'Saved on this computer'],
  'changedFirst': ['有变化在前', '有變化在前', 'Changed first'],
  'recent': ['最近关注', '最近關注', 'Recently followed'],
  'move': ['涨跌幅', '漲跌幅', 'Biggest move'],
  'item': ['物品', '物品', 'Item'],
  'lowest': ['现在最低卖价', '現在最低賣價', 'Lowest ask now'],
  'since': ['关注后涨跌', '關注後漲跌', 'Since following'],
  'listings': ['在售 / 最高收购', '在售 / 最高收購', 'Listed / best bid'],
  'changed': ['有变化', '有變化', 'Changed'],
  'then': ['关注时 ¤ {p}', '關注時 ¤ {p}', 'When followed ¤ {p}'],
  'flat': ['持平', '持平', 'Flat'],
  'noSell': ['暂无出售', '暫無出售', 'None for sale'],
  'onSale': ['{n} 条在售', '{n} 條在售', '{n} listed'],
  'new': ['+{n} 新增', '+{n} 新增', '+{n} new'],
  'bestBid': ['最高收购 {p}', '最高收購 {p}', 'Best bid {p}'],
  'quotes': ['看报价', '看報價', 'Quotes'],
  'unfollow': ['取消关注', '取消關注', 'Unfollow'],
  'unfollowed': ['已取消关注「{name}」', '已取消關注「{name}」', 'Unfollowed {name}'],
  'undo': ['撤销', '撤銷', 'Undo'],
  'more': ['再显示 {n} 件', '再顯示 {n} 件', 'Show {n} more'],
  'empty': [
    '还没有关注的物品。在物品页点「关注」，价格和在售的变化会出现在这里。',
    '還沒有關注的物品。在物品頁點「關注」，價格和在售的變化會出現在這裡。',
    'Nothing watched yet. Follow an item on its page and its price and listing changes show up here.',
  ],
  'loading': ['读取中…', '讀取中…', 'Loading…'],
  'unavailable': ['暂不可用', '暫不可用', 'Unavailable'],
};

String watchText(BuildContext context, String key) {
  final locale = marketLocale(context);
  return _copy[key]![locale == 'en'
      ? 2
      : locale == 'hant'
      ? 1
      : 0];
}

/// The 关注 tab (G3, 0.7.2; preview `watchlist-preview.html`, approved
/// 2026-10-21): what each followed item costs now against when it was
/// followed, changed items first. Local only; no server state.
class MarketplaceWatchPage extends StatefulWidget {
  const MarketplaceWatchPage(this.c, {super.key});
  final MarketplaceController c;
  @override
  State<MarketplaceWatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<MarketplaceWatchPage> {
  MarketplaceController get c => widget.c;
  String sort = 'changed';

  @override
  void initState() {
    super.initState();
    // The tab is built inside the hall's own build; start reading after it,
    // so the controller never notifies listeners mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(c.loadWatch());
    });
  }

  List<MarketWatchEntry> _sorted() {
    final entries = c.watchEntries;
    final order = {for (final (i, id) in c.favorites.indexed) id: i};
    int recent(MarketWatchEntry a, MarketWatchEntry b) =>
        order[a.id]!.compareTo(order[b.id]!);
    switch (sort) {
      case 'move':
        entries.sort((a, b) {
          final x = a.changePercent?.abs(), y = b.changePercent?.abs();
          if (x == null && y == null) return recent(a, b);
          if (x == null) return 1;
          if (y == null) return -1;
          return y.compareTo(x);
        });
      case 'recent':
        entries.sort(recent);
      default:
        entries.sort((a, b) {
          if (a.changed != b.changed) return a.changed ? -1 : 1;
          return recent(a, b);
        });
    }
    return entries;
  }

  Future<void> _unfollow(MarketWatchEntry entry) async {
    final snapshot = c.watchSnapshot(entry.id);
    final name = entry.item == null
        ? marketText(context, 'thisItem')
        : marketName(entry.item!, marketLocale(context));
    final messenger = ScaffoldMessenger.maybeOf(context);
    final undo = watchText(context, 'undo');
    final text = watchText(context, 'unfollowed').replaceAll('{name}', name);
    await c.toggleFavorite(entry.id);
    messenger?.showOnly(
      // QualityPass ②: 2.5 s, paused while pointed at so 撤销 stays reachable.
      starBridgeTimedSnackBar(
        content: Text(text),
        action: SnackBarAction(
          label: undo,
          onPressed: () => unawaited(
            c.toggleFavorite(entry.id, snapshot: snapshot),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final t = context.tokens;
      final entries = _sorted();
      final changed = entries.where((e) => e.changed).length;
      final header = MarketHeading(
        watchText(context, 'title'),
        leading: const FavoriteIcon(
          selected: true,
          size: 16,
          color: MarketplacePalette.heart,
        ),
        trailing: Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
            children: [
              TextSpan(
                text: watchText(
                  context,
                  'summary',
                ).replaceAll('{n}', '${c.favorites.length}'),
              ),
              if (changed > 0) ...[
                const TextSpan(text: ' · '),
                TextSpan(
                  text: watchText(
                    context,
                    'changedN',
                  ).replaceAll('{n}', '$changed'),
                  style: const TextStyle(color: MarketplacePalette.gold),
                ),
              ],
              TextSpan(text: ' · ${watchText(context, 'local')}'),
            ],
          ),
        ),
      );
      if (c.favorites.isEmpty) {
        return ListView(
          children: [
            header,
            const SizedBox(height: 16),
            MarketNotice(watchText(context, 'empty')),
          ],
        );
      }
      return LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 900;
          return ListView(
            key: const ValueKey('market-watch-list'),
            children: [
              Row(
                children: [
                  Expanded(child: header),
                  const SizedBox(width: 12),
                  MarketSubTabs(key: const Key('market-watch-sort'), [
                    for (final key in ['changed', 'recent', 'move'])
                      MarketSubTab(
                        watchText(
                          context,
                          key == 'changed' ? 'changedFirst' : key,
                        ),
                        selected: sort == key,
                        onTap: () => setState(() => sort = key),
                        controlKey: ValueKey(('market-watch-sort', key)),
                      ),
                  ]),
                ],
              ),
              const SizedBox(height: 12),
              if (!narrow) _columns(context),
              for (final entry in entries)
                _WatchRow(
                  c,
                  entry,
                  narrow: narrow,
                  unfollow: () => _unfollow(entry),
                ),
              if (c.favorites.length > c.watchLimit)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: marketTextAction(
                      key: const Key('market-watch-more'),
                      onPressed: () => unawaited(c.loadWatch(more: true)),
                      child: Text(
                        watchText(context, 'more').replaceAll(
                          '{n}',
                          '${(c.favorites.length - c.watchLimit).clamp(0, 24)}',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    },
  );

  Widget _columns(BuildContext context) {
    final style = TextStyle(
      fontSize: 11.5,
      color: context.tokens.colors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Row(
        children: [
          const SizedBox(width: 74),
          Expanded(flex: 5, child: Text(watchText(context, 'item'), style: style)),
          Expanded(flex: 3, child: Text(watchText(context, 'lowest'), style: style)),
          Expanded(flex: 3, child: Text(watchText(context, 'since'), style: style)),
          Expanded(flex: 4, child: Text(watchText(context, 'listings'), style: style)),
          const SizedBox(width: 132),
        ],
      ),
    );
  }
}

class _WatchRow extends StatelessWidget {
  const _WatchRow(
    this.c,
    this.entry, {
    required this.narrow,
    required this.unfollow,
  });
  final MarketplaceController c;
  final MarketWatchEntry entry;
  final bool narrow;
  final VoidCallback unfollow;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final item = entry.item;
    final name = item == null ? marketText(context, 'itemNameMissing') : marketName(item, marketLocale(context));
    final quiet = TextStyle(fontSize: 11.5, color: t.colors.textSecondary);
    final change = entry.changePercent;
    final Widget lowest = entry.failed
        ? Text(watchText(context, 'unavailable'), style: quiet)
        : !entry.loaded
        ? Text(watchText(context, 'loading'), style: quiet)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              entry.lowest == null
                  ? Text(watchText(context, 'noSell'), style: quiet)
                  : MarketGoldPrice(entry.lowest, size: 15),
              if (entry.thenPrice != null)
                Text(
                  watchText(context, 'then')
                      .replaceAll('{p}', marketPrice(context, entry.thenPrice)),
                  style: quiet,
                ),
            ],
          );
    final Widget since = change == null
        ? Text('—', style: quiet)
        : change.abs() < .05
        ? Text(watchText(context, 'flat'), style: quiet)
        : Text(
            '${change > 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: change > 0 ? t.colors.success : t.colors.danger,
            ),
          );
    final Widget listings = !entry.loaded
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: watchText(context, 'onSale')
                          .replaceAll('{n}', '${entry.count ?? 0}'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (entry.newListings > 0)
                      TextSpan(
                        text: '  ${watchText(context, 'new').replaceAll('{n}', '${entry.newListings}')}',
                        style: TextStyle(color: t.colors.accent),
                      ),
                  ],
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
              Text(
                watchText(context, 'bestBid').replaceAll(
                  '{p}',
                  entry.highest == null ? '—' : marketPrice(context, entry.highest),
                ),
                style: quiet,
              ),
            ],
          );
    final identity = Row(
      children: [
        SizedBox(
          width: 60,
          height: 48,
          child: MarketArt(
            item == null ? null : marketThumbnail(item),
            category: item == null ? 0 : marketCategoryOf(item),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: t.typography.emphasisWeight,
                ),
              ),
              if (entry.changed)
                MarketSlantTag(
                  watchText(context, 'changed'),
                  color: MarketplacePalette.gold,
                ),
            ],
          ),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        marketButtonAction(
          FilledButton(
            onPressed: () => c.openItem(entry.id),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              shape: const RoundedRectangleBorder(),
            ),
            child: Text(watchText(context, 'quotes')),
          ),
          key: ValueKey(('market-watch-quotes', entry.id)),
        ),
        const SizedBox(width: 6),
        StarBridgeNativeIconAction(
          controlKey: ValueKey(('market-watch-unfollow', entry.id)),
          label: watchText(context, 'unfollow'),
          onActivate: c.savingPreferences || c.preferencesFailed
              ? null
              : (_) => unfollow(),
          icon: const FavoriteIcon(
            selected: true,
            size: 18,
            color: MarketplacePalette.heart,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: StarBridgeActionRow(
        controlKey: ValueKey(('market-watch-entry', entry.id)),
        inheritContentStyle: true,
        baseRadius: 0,
        semanticLabel: name,
        onActivate: (_, _) => c.openItem(entry.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: t.surfaces.panel.fill,
            border: Border(
              left: BorderSide(
                width: 3,
                color: entry.changed
                    ? MarketplacePalette.gold
                    : marketLine(context),
              ),
              bottom: BorderSide(color: marketLine(context)),
            ),
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: lowest),
                        const SizedBox(width: 8),
                        since,
                        const SizedBox(width: 12),
                        actions,
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 5, child: identity),
                    Expanded(flex: 3, child: lowest),
                    Expanded(flex: 3, child: since),
                    Expanded(flex: 4, child: listings),
                    SizedBox(width: 132, child: Align(alignment: Alignment.centerRight, child: actions)),
                  ],
                ),
        ),
      ),
    );
  }
}
