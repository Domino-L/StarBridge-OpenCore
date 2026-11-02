import '../../shared/guide/guide_empty_state.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/icons/marketplace_icon.dart';
import 'marketplace_trade_copy.dart';
import 'marketplace_trade_feedback.dart';

import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_action_row.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_port.dart';
import 'marketplace_prefetch.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_unified.dart';
import 'marketplace_activity_rail.dart';
import 'marketplace_publish_entry.dart' show openMarketPublish;
import 'marketplace_trade_style.dart' show tradePrimaryStyle;
import 'marketplace_trades_controller.dart';
import 'marketplace_widgets.dart';

import 'marketplace_trade_status.dart';
import 'marketplace_trade_sheet.dart';
export 'marketplace_trade_status.dart';
export 'marketplace_trade_sheet.dart';
export 'marketplace_trade_actions.dart' show tradeDialog;

class MarketplaceTradesPage extends StatefulWidget {
  const MarketplaceTradesPage(this.c, {super.key});
  final MarketplaceController c;
  @override
  State<MarketplaceTradesPage> createState() => _TradesPageState();
}

class _TradesPageState extends State<MarketplaceTradesPage> {
  bool history = false;
  String role = 'all';

  @override
  void initState() {
    super.initState();
    widget.c.trades.addListener(_openPending);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPending());
  }

  @override
  void dispose() {
    widget.c.trades.removeListener(_openPending);
    super.dispose();
  }

  // A trade reminder (CX-T23) asked for one transaction: read it by its ref,
  // then show the same sheet a row tap shows. An expired ref stays on the list.
  Future<void> _openPending() async {
    if (!mounted || widget.c.trades.pendingRef == null) return;
    final ref = widget.c.trades.takePendingRef();
    if (ref == null) return;
    final row = await widget.c.trades.openRef(ref);
    if (!mounted || row == null) return;
    await showTrade(context, widget.c, row);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.c.trades;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final filtered = t.rows
            .where(
              (r) =>
                  (role == 'all' || r['actorRole'] == role) &&
                  (history
                      ? [3, 4].contains(r['deliveryStatus']) &&
                            tradeAction(r) == null
                      : ![3, 4].contains(r['deliveryStatus']) ||
                            tradeAction(r) != null),
            )
            .toList();
        final mine = filtered.where((r) => tradeAction(r) != null).toList();
        final waiting = filtered.where((r) => tradeAction(r) == null).toList();
        final active = t.rows
            .where(
              (r) =>
                  (role == 'all' || r['actorRole'] == role) &&
                  (![3, 4].contains(r['deliveryStatus']) ||
                      tradeAction(r) != null),
            )
            .length;
        final entries = <(String, List<MarketRow>)>[
          if (mine.isNotEmpty) (tradeText(context, '需要我处理'), mine),
          if (waiting.isNotEmpty)
            (
              history ? tradeText(context, '已结束') : tradeText(context, '等待对方'),
              waiting,
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 我的交易 layout A: one row, title then filters; no repeated heading.
            MarketSectionBar(
              tradeText(context, '交易'),
              filters: [
                // The hall's second-level tabs instead of boxed segments.
                MarketSubTabs(key: const Key('market-trades-history'), [
                  MarketSubTab(
                    tradeText(context, '进行中'),
                    count: active,
                    selected: !history,
                    onTap: () => setState(() => history = false),
                  ),
                  MarketSubTab(
                    tradeText(context, '已结束'),
                    selected: history,
                    onTap: () => setState(() => history = true),
                  ),
                ]),
                MarketSubTabs(key: const Key('market-trades-role'), [
                  for (final (value, label) in [
                    ('all', '全部'),
                    ('buyer', '我买的'),
                    ('seller', '我卖的'),
                  ])
                    MarketSubTab(
                      tradeText(context, label),
                      selected: role == value,
                      onTap: () => setState(() => role = value),
                    ),
                ]),
              ],
            ),
            if (t.error != null) TradeFailure(widget.c, retry: t.refresh),
            if (t.loading && t.rows.isEmpty) LinearProgressIndicator(),
            // A new user with no trades at all gets the guide's empty state
            // (in the list below); a filter that matches nothing gets this one.
            if (entries.isEmpty &&
                t.ended &&
                !t.loading &&
                t.error == null &&
                !(t.rows.isEmpty && GuideEmptyState.active(context)))
              MarketActivityEmpty(
                key: const Key('market-trades-empty'),
                title: tradeText(
                  context,
                  history ? '还没有已结束的交易' : '还没有进行中的交易',
                ),
                body: tradeText(
                  context,
                  history
                      ? '交易完成或取消后会出现在这里。'
                      : '在市场里下单，或者发布挂单等别人来买，交易就会出现在这里。已经结束的交易在“已结束”里。',
                ),
                actions: [
                  OutlinedButton(
                    key: const Key('market-trades-empty-market'),
                    onPressed: () => widget.c.tab(1),
                    child: Text(tradeText(context, '去市场逛逛')),
                  ),
                  FilledButton(
                    key: const Key('market-trades-empty-publish'),
                    style: tradePrimaryStyle(context),
                    onPressed: () => openMarketPublish(context, widget.c),
                    child: Text(tradeText(context, '发布挂单')),
                  ),
                ],
              )
            else
            Expanded(
              child: MarketPrefetch(
                read: MarketRead({
                  'rows': t.rows,
                  'total': t.total,
                  'pageEnd': t.ended,
                }, DateTime.now()),
                loading: t.loading,
                failed: t.error != null,
                load: () => t.refresh(more: true),
                child: ListView.builder(
                  itemCount: entries.length + 1,
                  itemBuilder: (context, i) {
                    if (i == entries.length) {
                      if (t.error == null &&
                          t.ended &&
                          t.rows.isEmpty &&
                          GuideEmptyState.active(context)) {
                        return GuideEmptyState(
                          'trades',
                          onPrimary: () => widget.c.tab(1),
                        );
                      }
                      return Padding(
                        padding: EdgeInsets.all(24),
                        child: t.error != null
                            ? marketTextAction(
                                key: const Key('market-trades-retry'),
                                onPressed: t.refresh,
                                child: Text(tradeText(context, '加载失败 · 重试')),
                              )
                            : Text(
                                t.loading
                                    ? tradeText(context, '正在读取交易…')
                                    : t.ended
                                    ? (t.rows.isEmpty
                                          ? tradeText(context, '还没有交易，去市场看看。')
                                          : tradeText(context, '已显示全部'))
                                    : '',
                                textAlign: TextAlign.center,
                              ),
                      );
                    }
                    final (label, rows) = entries[i];
                    final urgent = label == tradeText(context, '需要我处理');
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            top: i == 0 ? 0 : 14,
                            bottom: 8,
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: urgent
                                        ? MarketplacePalette.attention
                                        : context.tokens.colors.textPrimary,
                                  ),
                                ),
                                TextSpan(
                                  text: '  ${rows.length}',
                                  style: TextStyle(
                                    fontFamily:
                                        context.tokens.typography.monoFamily,
                                    color: context.tokens.colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                        DecoratedBox(
                          position: DecorationPosition.foreground,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: context.tokens.surfaces.panel.border,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Column(
                              children: [
                                for (final (j, r) in rows.indexed)
                                  TradeRow(
                                    r,
                                    last: j == rows.length - 1,
                                    onTap: () =>
                                        showTrade(context, widget.c, r),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class TradeRow extends StatelessWidget {
  const TradeRow(this.row, {required this.onTap, this.last = false, super.key});
  final MarketRow row;
  final VoidCallback onTap;
  final bool last;
  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.surfaces.panel.fill,
    child: StarBridgeActionRow(
      inheritContentStyle: true,
      controlKey: ValueKey(('market-trade-row', row['transactionNumber'])),
      baseRadius: 0,
      onActivate: (_, _) => onTap(),
      child: Container(
        constraints: BoxConstraints(minHeight: 64),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 3,
              color: tradeAction(row) != null
                  ? MarketplacePalette.attention
                  : Colors.transparent,
            ),
            bottom: last
                ? BorderSide.none
                : BorderSide(color: marketLine(context)),
          ),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 44,
              child: MarketArt.of(row),
            ),
            SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tradeItemName(context, row),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 3),
                  Row(
                    children: [
                      TradeRole(row),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '×${row['number'] ?? ''} · ${row['actorRole'] == 'seller' ? tradeText(context, '买家') : tradeText(context, '卖家')} ${row['counterpartyName'] ?? tradeText(context, '资料待更新')}',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.tokens.colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            SizedBox(
              width: MediaQuery.sizeOf(context).width < 1100 ? 150 : 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tradeText(context, tradeStatus(row)),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tradeAction(row) != null
                          ? MarketplacePalette.attention
                          : [3, 4].contains(row['deliveryStatus'])
                          ? context.tokens.colors.textSecondary
                          : context.tokens.colors.accent,
                    ),
                  ),
                  DefaultTextStyle.merge(
                    style: TextStyle(fontSize: 11),
                    child: TradeDeadline(row, compact: true),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 150,
              child: Align(
                alignment: Alignment.centerRight,
                child: MarketPrice(tradeItemsTotal(row)),
              ),
            ),
            SizedBox(
              width: 100,
              child: Align(
                alignment: Alignment.centerRight,
                child: tradeAction(row) != null
                    ? marketButtonAction(OutlinedButton(
                        onPressed: onTap,
                        style: OutlinedButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          minimumSize: Size(0, 30),
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          foregroundColor: MarketplacePalette.attention,
                          side: BorderSide(
                            color: MarketplacePalette.attention.withValues(
                              alpha: .6,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        child: Text(tradeActionLabel(context, row)),
                      ), key: ValueKey(('market-trade-row-action', row['transactionNumber'])))
                    : MarketplaceIcon(
                        MarketplaceGlyph.next,
                        size: 16,
                        color: context.tokens.colors.textSecondary,
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String tradeActionLabel(BuildContext context, MarketRow row) =>
    {
      'ship': tradeText(context, '去发货'),
      'review': tradeText(context, '去评价'),
    }[tradeAction(row)] ??
    tradeText(context, tradeLabels[tradeAction(row)]!);

class TradeTodo extends StatelessWidget {
  const TradeTodo(this.c, {super.key});
  final MarketplaceController c;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c.trades,
    builder: (context, _) {
      final rows = c.trades.todo;
      if (rows.isEmpty) return SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: MarketHeading(
                    tradeText(context, '待我处理'),
                    trailing: Text(
                      '${rows.length}${c.trades.ended ? '' : '+'} ${tradeText(context, '笔交易')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.tokens.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
                marketTextAction(
                  key: const Key('market-trade-todo-all'),
                  onPressed: () => c.tab(3),
                  child: Text(tradeText(context, '全部交易 →')),
                ),
              ],
            ),
            SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, size) {
                final cards = rows
                    .take(3)
                    .map(
                      (r) => TradeTodoCard(
                        r,
                        onTap: () => showTrade(context, c, r),
                      ),
                    )
                    .toList();
                if (MediaQuery.sizeOf(context).width < 980) {
                  return Column(
                    children: [
                      for (final card in cards)
                        Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: card,
                        ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) SizedBox(width: 10),
                      Expanded(child: cards[i]),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

class TradeTodoCard extends StatelessWidget {
  const TradeTodoCard(this.row, {required this.onTap, super.key});
  final MarketRow row;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final action = tradeAction(row);
    final edge = action != null
        ? MarketplacePalette.attention
        : t.colors.accent;
    final who = row['counterpartyName'];
    final label = row['actorRole'] == 'seller'
        ? tradeText(context, '买家')
        : tradeText(context, '卖家');
    return Material(
      color: t.surfaces.panel.fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: t.surfaces.panel.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: StarBridgeActionRow(
        inheritContentStyle: true,
        controlKey: ValueKey(('market-trade-todo', row['transactionNumber'])),
        baseRadius: 9,
        onActivate: (_, _) => onTap(),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(width: 3, color: edge)),
          ),
          padding: EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 52,
                child: MarketArt.of(row),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tradeItemName(context, row)} ×${row['number'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '$label ${who ?? tradeText(context, '资料待更新')}',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.colors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tradeText(context, tradeStatus(row)),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                              color: edge,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: DefaultTextStyle.merge(
                            style: TextStyle(fontSize: 11),
                            child: TradeDeadline(row, compact: true),
                          ),
                        ),
                        SizedBox(width: 8),
                        marketButtonAction(OutlinedButton(
                          onPressed: onTap,
                          style: OutlinedButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            minimumSize: Size(0, 30),
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            foregroundColor: t.colors.textPrimary,
                            side: BorderSide(color: t.surfaces.panel.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          child: Text(
                            action == null
                                ? tradeText(context, '查看')
                                : tradeActionLabel(context, row),
                          ),
                        ), key: ValueKey(('market-trade-todo-action', row['transactionNumber']))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
