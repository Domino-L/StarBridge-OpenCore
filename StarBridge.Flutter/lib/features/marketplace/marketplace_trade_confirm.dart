import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_trade_profile.dart';
import 'marketplace_trade_profile_copy.dart';
import 'marketplace_trade_copy.dart';

import 'package:flutter/material.dart';

import 'marketplace_controller.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_copy.dart';
import 'marketplace_details.dart';
import 'marketplace_order_sheet.dart';
import 'marketplace_port.dart';
import 'marketplace_trades_page.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_widgets.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

Future<void> confirmMarketTrade(
  BuildContext context,
  MarketplaceController c,
  MarketRow row,
) {
  // Last guard: never open a trade against your own listing.
  if (marketIsMine(row)) {
    ScaffoldMessenger.maybeOf(context)?.showOnly(
      starBridgeTimedSnackBar(content: Text(marketText(context, 'mineHint'))),
    );
    return Future.value();
  }
  return tradeMotionDialog<void>(context, (_) => _ConfirmTrade(c, row));
}

class _ConfirmTrade extends StatefulWidget {
  const _ConfirmTrade(this.c, this.row);
  final MarketplaceController c;
  final MarketRow row;
  @override
  State<_ConfirmTrade> createState() => _ConfirmTradeState();
}

class _ConfirmTradeState extends State<_ConfirmTrade> {
  int quantity = 1, method = 0;
  bool submitted = false;
  final fee = TextEditingController(text: '0');
  late final contextRevision = widget.c.contextRevision;
  @override
  void dispose() {
    fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, t = c.trades, r = widget.row;
    final max = marketNumber(r['availableQuantity'] ?? r['remainingQuantity'])
        ?.toInt();
    final location = marketNumber(r['locationId'])?.toInt();
    final unit = marketNumber(r['unitPrice']);
    final buy = r['creatorType'] == 1;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) => PopScope(
        canPop: !t.pending,
        child: Dialog(
          backgroundColor: context.tokens.surfaces.floating.fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r['seller'] is String
                                ? tradeText(
                                    context,
                                    buy ? 'cfBuyFrom' : 'cfSellTo',
                                    {'name': r['seller'] as String},
                                  )
                                : buy
                                ? tradeText(context, '确认购买')
                                : tradeText(context, '确认出售给他'),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        StarBridgeNativeIconAction(
                          key: const Key('market-confirm-close'),
                          label: tradeText(context, '关闭'),
                          onActivate: t.pending
                              ? null
                              : (source) => dismissStarBridgeDialog<void>(context, source: source),
                          icon: MarketplaceIcon(
                            MarketplaceGlyph.close,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox.square(
                          dimension: 52,
                          child: MarketArt.of(r),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tradeItemName(context, {
                                  ...r,
                                  'itemName':
                                      r['itemName'] ??
                                      c.blocks['item']?.data['itemName'],
                                }),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                [
                                  if (unit != null || max != null)
                                    tradeText(context, 'cfMeta', {
                                      'price': marketMoney(unit),
                                      'left': '${max ?? '—'}',
                                    }),
                                  if (marketQuality(r) case final q?)
                                    tradeText(context, 'cfQuality', {'q': q}),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: context.tokens.colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 10),
                        Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.tokens.surfaces.ground.fill,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: context.tokens.surfaces.panel.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StarBridgeNativeIconAction(
                                key: const Key('market-confirm-quantity-remove'),
                                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                                label: tradeText(context, '数量'),
                                onActivate: t.pending || quantity <= 1
                                    ? null
                                    : (_) => setState(() => quantity--),
                                icon: MarketplaceIcon(
                                  MarketplaceGlyph.remove,
                                  size: 16,
                                ),
                              ),
                              SizedBox(
                                width: 36,
                                child: Text(
                                  '$quantity',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily:
                                        context.tokens.typography.monoFamily,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              StarBridgeNativeIconAction(
                                key: const Key('market-confirm-quantity-add'),
                                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                                autofocus: max != null && max > quantity,
                                label: tradeText(context, '数量'),
                                onActivate:
                                    t.pending || max == null || quantity >= max
                                    ? null
                                    : (_) => setState(() => quantity++),
                                icon: MarketplaceIcon(
                                  MarketplaceGlyph.add,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (unit != null) ...[
                      SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            tradeText(context, 'cfTotal'),
                            style: TextStyle(
                              color: context.tokens.colors.textSecondary,
                            ),
                          ),
                          Spacer(),
                          MarketPrice(unit * quantity, size: 22),
                        ],
                      ),
                    ],
                    SizedBox(height: 10),
                    Container(height: 1, color: marketLine(context)),
                    SizedBox(height: 6),
                    _ConfirmRow(
                      tradeText(context, 'cfLocation'),
                      Text(marketLocation(context, r)),
                    ),
                    _ConfirmRow(
                      tradeText(context, 'cfHours'),
                      Text(marketTradeTime(context, r)),
                    ),
                    _ConfirmRow(
                      tradeText(context, 'cfCounterparty'),
                      Text(
                        '● ${marketText(context, r['presence'] as String? ?? 'unknown')}'
                        '${r['point'] == null ? '' : ' · ★ ${r['point']}'}',
                      ),
                    ),
                    if (r['remark'] is String &&
                        (r['remark'] as String).isNotEmpty)
                      _ConfirmRow(
                        tradeText(context, 'cfRemark'),
                        Text(r['remark'] as String),
                      ),
                    _ConfirmRow(
                      tradeText(context, '交付方式'),
                      Container(
                        height: 34,
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: context.tokens.surfaces.ground.fill,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: context.tokens.surfaces.panel.border,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: StarBridgeCompactSelect<int>(
                            identity: 'market-confirm-delivery',
                            controlKey: const Key('market-confirm-delivery'),
                            semanticLabel: tradeText(context, '交付方式'),
                            autofocus: max == null || max <= quantity,
                            value: method,
                            isDense: true,
                            style: Theme.of(context).textTheme.bodyMedium,
                            options: [
                              for (var i = 0; i < 4; i++)
                                StarBridgeSelectOption(
                                  value: i,
                                  label: [
                                    tradeText(context, '面交'),
                                    tradeText(context, '代运'),
                                    tradeText(context, '自提'),
                                    tradeText(context, '其他'),
                                  ][i],
                                ),
                            ],
                            onSelected: t.pending
                                ? null
                                : (v, _) => setState(() => method = v),
                          ),
                        ),
                      ),
                    ),
                    _ConfirmRow(
                      tradeText(context, '约定运费（UEC）'),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: fee,
                          enabled: !t.pending,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: context.tokens.typography.monoFamily,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: context.tokens.surfaces.ground.fill,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: context.tokens.surfaces.panel.border,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    SizedBox(height: 14),
                    TradeNoticeBox(
                      buy
                          ? tradeText(
                              context,
                              '发起后直接进入待发货。卖家 48 小时内未发货，SCM 会自动取消。',
                            )
                          : tradeText(context, '收购方同意后才进入待发货，请先确认数量和交付安排。'),
                      warning: true,
                    ),
                    if (location == null || max == null)
                      Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          tradeText(context, '当前报价缺少交易地点或库存，请刷新报价后再试。'),
                        ),
                      ),
                    if (submitted && t.writeError != null)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: TradeFailure(
                          c,
                          writing: true,
                          retry: () async {
                            if (!t.writeUncertain) return;
                            final source = StarBridgeActivationOrigin.sourceOf(context);
                            if (await t.inspectUncertainWrite() &&
                                context.mounted) {
                              dismissStarBridgeDialog<void>(context, source: source);
                              c.tab(3);
                            }
                          },
                        ),
                      ),
                    if (submitted && (t.writeErrorCode == 'marketplace.trade_time_required' || t.writeErrorCode == 'marketplace.contact_required'))
                      marketButtonAction(TextButton(onPressed: t.pending ? null : () async {
                        final result = await editTradeProfile(context, c, missing: t.writeErrorCode);
                        if (mounted && c.contextRevision == contextRevision && result != null) {
                          setState(() => submitted = false);
                        }
                      }, child: Text(tradeProfileText(context, 'prepare'))), key: const Key('market-confirm-profile')),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        marketButtonAction(TextButton(
                          onPressed: t.pending
                              ? null
                              : () {
                                  final hostContext = Navigator.of(context)
                                      .overlay!
                                      .context;
                                  dismissStarBridgeDialog<void>(context,
                                      source: StarBridgeActivationOrigin.sourceOf(context));
                                  showMarketOrder(hostContext, c, r);
                                },
                          child: Text(tradeText(context, '查看订单详情')),
                        ), key: const Key('market-confirm-details')),
                        const Spacer(),

                        marketButtonAction(OutlinedButton(
                          style: tradeCancelStyle(),
                          onPressed: t.pending
                              ? null
                              : () => dismissStarBridgeDialog<void>(context,
                                  source: StarBridgeActivationOrigin.sourceOf(context)),
                          child: Text(tradeText(context, '取消')),
                        ), key: const Key('market-confirm-cancel')),
                        SizedBox(width: 8),
                        if (!t.writeUncertain)
                          marketButtonAction(FilledButton(
                            style: tradePrimaryStyle(context),
                            onPressed:
                                t.pending ||
                                    t.writeUncertain ||
                                    location == null ||
                                    max == null ||
                                    max < quantity ||
                                    num.tryParse(fee.text) == null ||
                                    !(num.tryParse(fee.text) ?? double.nan)
                                        .isFinite ||
                                    (num.tryParse(fee.text) ?? 0) >
                                        1000000000000000 ||
                                    (num.tryParse(fee.text) ?? -1) < 0 ||
                                    contextRevision != c.contextRevision
                                ? null
                                : () async {
                                    final source = StarBridgeActivationOrigin.sourceOf(context);
                                    setState(() => submitted = true);
                                    final hostContext = Navigator.of(context)
                                        .overlay!
                                        .context;
                                    final number = await t.submit('create', {
                                      'orderNumber': r['orderNumber'],
                                      'number': quantity,
                                      'locationId': location,
                                      'deliveryMethod': method,
                                      'shippingFee': num.parse(fee.text),
                                    });
                                    if (!context.mounted || number == null) {
                                      return;
                                    }
                                    showTradeSuccess(
                                      hostContext,
                                      message: tradeText(
                                        context,
                                        buy ? '交易已发起，等待卖家发货' : '交易已发起，等待收购方同意',
                                      ),
                                      open: () => showTrade(hostContext, c, {
                                        'transactionNumber': number,
                                      }),
                                    );
                                    dismissStarBridgeDialog<void>(context, source: source);
                                  },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (t.pending) ...[
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                ],
                                Text(
                                  t.pending
                                      ? tradeText(context, '正在发起…')
                                      : !submitted || t.writeError == null
                                      ? tradeText(context, '确认发起')
                                      : tradeText(context, '重试'),
                                ),
                              ],
                            ),
                          ), key: const Key('market-confirm-submit')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow(this.label, this.value);
  final String label;
  final Widget value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: context.tokens.colors.textSecondary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
              child: value,
            ),
          ),
        ),
      ],
    ),
  );
}
