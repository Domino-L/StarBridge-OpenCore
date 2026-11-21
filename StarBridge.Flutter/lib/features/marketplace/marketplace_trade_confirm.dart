import 'dart:async';
import 'marketplace_order_full.dart';
import 'marketplace_order_full_copy.dart';
import 'marketplace_display_copy.dart';
import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_trade_profile.dart';
import 'marketplace_trade_profile_copy.dart';
import 'marketplace_trade_copy.dart';
import 'marketplace_bundle_copy.dart';

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
  MarketRow row, {
  bool fromOrderDetail = false,
}) {
  // Last guard: never open a trade against your own listing.
  if (marketIsMine(row)) {
    ScaffoldMessenger.maybeOf(context)?.showOnly(
      starBridgeTimedSnackBar(content: Text(marketText(context, 'mineHint'))),
    );
    return Future.value();
  }
  return tradeMotionDialog<void>(context, (_) => _ConfirmTrade(c, row, fromOrderDetail));
}

class _ConfirmTrade extends StatefulWidget {
  const _ConfirmTrade(this.c, this.row, this.fromOrderDetail);
  final bool fromOrderDetail;
  final MarketplaceController c;
  final MarketRow row;
  @override
  State<_ConfirmTrade> createState() => _ConfirmTradeState();
}

class _ConfirmTradeState extends State<_ConfirmTrade> {
  List<MarketRow>? _locations;
  bool _locationsLoading = true;
  int? _location;
  Future<void> _readLocations() async {
    setState(() => _locationsLoading = true);
    final rows = await widget.c.tradeLocations.load();
    if (!mounted || contextRevision != widget.c.contextRevision) return;
    setState(() {
      _locations = rows;
      _locationsLoading = false;
      final last = widget.c.tradeLocations.selected;
      _location = rows?.any((r) => marketNumber(r['id']) == last) == true ? last : null;
    });
  }
  MarketRow? _fullRow;
  bool _fullLoading = false;
  bool get _incomplete => widget.row['displayType'] == 2 &&
      MarketOrderFull.needs(_fullRow ?? widget.row);

  // MK3 cap: the read tradable quantity; else the list row's own (a full read
  // may carry it as null); else remaining. One rule for the clamp and build.
  int? get _max => marketNumber(_fullRow?['availableQuantity'] ??
          widget.row['availableQuantity'] ??
          _fullRow?['remainingQuantity'] ?? widget.row['remainingQuantity'])
      ?.toInt();

  @override
  void initState() {
    super.initState();
    // Bind the dialog to the account it opened under, before any read.
    contextRevision = widget.c.contextRevision;
    unawaited(_readFull());
    unawaited(_readLocations());
  }

  Future<void> _readFull({bool retry = false}) async {
    setState(() => _fullLoading = true);
    final result = await widget.c.fullOrders.fullOrder(widget.row,
        retry: retry, quantity: true);
    if (!mounted || contextRevision != widget.c.contextRevision) return;
    setState(() {
      _fullRow = result;
      _fullLoading = false;
      final max = _max;
      if (max != null && max > 0 && quantity > max) quantity = max;
    });
  }

  int quantity = 1, method = 0;
  bool submitted = false;
  final fee = TextEditingController(text: '0');
  late final int contextRevision;
  @override
  void dispose() {
    fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, t = c.trades, r = _fullRow ?? widget.row;
    final max = _max;
    final location = _locationsLoading || _locations == null ? null : _location;
    final unit = marketNumber(r['unitPrice']);
    final buy = r['creatorType'] == 1;
    final checklist = marketIsChecklist(r);
    final contents = marketRows(r['items']);
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
                            overflow: fadeOverflow(context),
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
                                checklist
                                    ? marketOrderTitle(context, r)
                                    : tradeItemName(context, r).isNotEmpty
                                    ? tradeItemName(context, r)
                                    // The open item page's localized name, but
                                    // only when it is this order's own item.
                                    : c.blocks['item']?.data['id'] != null &&
                                          c.blocks['item']?.data['id'] ==
                                              marketItemId(r)
                                    ? tradeItemName(context, c.blocks['item']!.data)
                                    : marketOrderTitle(context, r),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 3),
                              if (marketNumber(_fullRow?['availableQuantity']) case final available?)
                                Text('${marketDisplayText(context, 'available')} ${available.toInt()}'),
                              if (!checklist && _fullLoading)
                                Text(orderFullText(context, 'loading')),
                              if (!_fullLoading && !_incomplete &&
                                  marketNumber(_fullRow?['availableQuantity']) == null)
                                Text(marketDisplayText(context, 'quantityMissing')),
                              if (checklist && _incomplete) ...[
                                Text(orderFullText(context, _fullLoading ? 'loading' : 'blocked')),
                                if (!_fullLoading) TextButton(
                                  key: const Key('market-confirm-full-retry'),
                                  onPressed: () => _readFull(retry: true),
                                  child: Text(orderFullText(context, 'retry')),
                                ),
                              ],
                              if (checklist) ...[
                                for (final item in contents.take(4))
                                  Text('${marketName(item, marketLocale(context))} × ${marketNumber(item['quantity'])?.toInt() ?? 1}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (contents.length > 4)
                                  Text(bundleText(context, '等 {n} 件', {'n': '${contents.length - 4}'})),
                              ],
                              Text(
                                [
                                  if (unit != null || max != null)
                                    checklist ? '${bundleText(context, '每套价格')} ${marketMoney(unit)} · ${max ?? '—'} ${bundleText(context, '套')}' : tradeText(context, 'cfMeta', {
                                      'price': marketMoney(unit),
                                      'left': '${marketNumber(r['remainingQuantity'])?.toInt() ?? '—'}',
                                    }),
                                  if (!checklist && marketQuality(r) != null)
                                    tradeText(context, 'cfQuality', {'q': marketQuality(r)!}),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: fadeOverflow(context),
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
                                child: FittedBox(fit: BoxFit.scaleDown, child: Text(
                                  '$quantity ${bundleText(context, checklist ? '套' : '件')}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily:
                                        context.tokens.typography.monoFamily,
                                    fontSize: 15,
                                  ),
                                )),
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
                      tradeText(context, '对方的地点'),
                      Text(marketLocation(context, r)),
                    ),
                    _ConfirmRow(
                      tradeText(context, buy ? '收货位置' : '发货位置'),
                      _locationsLoading ? const LinearProgressIndicator()
                        : _locations == null ? Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(tradeText(context, '地点读取失败')),
                            TextButton(onPressed: _readLocations,
                              child: Text(tradeText(context, '重试'))),
                          ])
                        : StarBridgeCompactSelect<int>(
                            identity: 'market-confirm-location',
                            controlKey: const Key('market-confirm-location'),
                            semanticLabel: tradeText(context, buy ? '收货位置' : '发货位置'),
                            placeholder: tradeText(context, '请选择地点'),
                            isExpanded: true,
                            value: location,
                            options: [
                              for (final r in _locations!)
                                StarBridgeSelectOption(
                                  value: marketNumber(r['id'])!.toInt(),
                                  label: marketName(r, marketLocale(context), field: 'name')),
                            ],
                            onSelected: t.pending ? null : (v, _) => setState(() {
                              _location = v;
                              c.tradeLocations.choose(v);
                            }),
                          ),
                      key: const Key('market-confirm-location-row'),
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
                    if (max == null)
                      Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          tradeText(context, '当前报价缺少交易地点或库存，请刷新报价后再试。'),
                        ),
                      ),
                    if (t.writeUncertain || submitted && t.writeError != null)
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
                    if (!c.profileEditedInClient && submitted && (t.writeErrorCode == 'marketplace.trade_time_required' || t.writeErrorCode == 'marketplace.contact_required'))
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
                                  if (!widget.fromOrderDetail) showMarketOrder(hostContext, c, r);
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
                                    _incomplete ||
                                    _fullLoading ||
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
  const _ConfirmRow(this.label, this.value, {super.key});
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
