import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_segmented_control.dart';
import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_listings_controller.dart';
import 'marketplace_listing_errors.dart';
import 'marketplace_listing_copy.dart';
import 'marketplace_details.dart';
import 'marketplace_port.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_widgets.dart';
import 'marketplace_trade_style.dart';

import 'marketplace_listing_publish_widgets.dart';
import 'marketplace_listing_components.dart';
import 'marketplace_listing_item_picker.dart';
import 'marketplace_quality_widgets.dart' show marketTierPriceDelta;

class ListingPublishDialog extends StatefulWidget {
  const ListingPublishDialog(
    this.c,
    this.draft, {
    this.initialStep = 0,
    this.editProfile,
    super.key,
  });
  final MarketplaceListingsController c;
  final ListingDraft draft;
  final int initialStep;
  final VoidCallback? editProfile;
  @override
  State<ListingPublishDialog> createState() => _PublishState();
}

/// Quantity − / + read as part of the field: no fill or outline of their own.
const _stepperStyle = ButtonStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.transparent),
  side: WidgetStatePropertyAll(BorderSide.none),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
  ),
  visualDensity: VisualDensity.compact,
);

class _PublishState extends State<ListingPublishDialog> {
  late int step = widget.initialStep;
  late bool manifestForm = d.manifestId != null;

  String? error;
  late final quantityInput = TextEditingController(text: d.quantity);
  @override
  void initState() {
    super.initState();
    unawaited(widget.c.loadCategories());
  }

  @override
  void dispose() {
    quantityInput.dispose();
    super.dispose();
  }

  void adjustQuantity(int value) => setState(() {
    d.quantity = '$value';
    quantityInput.text = d.quantity;
  });
  // The wizard owns the draft it opened with. Dialog routes may rebuild their
  // builder (suite/theme relays), handing over a fresh draft object; adopting
  // it would silently drop the user's picks.
  late final ListingDraft d = widget.draft;
  String get itemName => d.manifestId == null
      ? '${d.item['name'] ?? listingText(context, '名称待更新')}'
      : '${widget.c.manifests.where((r) => r['id'] == d.manifestId).firstOrNull?['name'] ?? d.item['name'] ?? listingText(context, '清单')}';

  /// Market reference value; unknown is "暂无", never a dash or 0.
  String _ref(Object? value) =>
      marketNumber(value) == null
      ? listingText(context, '暂无')
      : marketMoney(value);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      final c = widget.c,
          full =
              widget.c.limit != null && widget.c.rows.length >= widget.c.limit!;
      final t = context.tokens;
      final sideColor = listingSideColor(context, d.side);
      return PopScope(
        canPop: !c.pending,
        child: Dialog(
          backgroundColor: t.surfaces.floating.fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: t.surfaces.floating.border),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            // The item step browses like 市场: tree + grid need the room.
            width: step == 1 && !manifestForm
                ? (MediaQuery.sizeOf(context).width - 48).clamp(560.0, 860.0)
                : 560,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: ExcludeFocus(
                excluding: c.pending,
                child: AbsorbPointer(
                  absorbing: c.pending,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              listingText(context, '发布挂单'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            // The chosen side stays visible on every step.
                            ListingSideTag(d.side),
                            const Spacer(),
                            StarBridgeNativeIconAction(
                              controlKey: const Key('market-publish-close'),
                              label: listingText(context, '关闭'),
                              onActivate: c.pending
                                  ? null
                                  : (source) => dismissStarBridgeDialog<void>(
                                      context,
                                      source: source,
                                    ),
                              icon: const MarketplaceIcon(
                                MarketplaceGlyph.close,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ListingWizardSteps(
                          step,
                          key: ValueKey('publish-step-$step'),
                          color: sideColor,
                        ),
                        const SizedBox(height: 18),
                        if (full)
                          TradeNoticeBox(
                            listingText(
                              context,
                              '挂单已满。先下架或删除一些挂单，或者提升信誉增加上限。',
                            ),
                            danger: true,
                          )
                        else if (step == 0)
                          ..._typeStep(c)
                        else if (step == 1)
                          ..._itemStep(c)
                        else if (step == 2)
                          ..._priceStep(c)
                        else
                          ..._confirmStep(c),
                        if (error != null || c.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: TradeNoticeBox(
                              (error == null
                                      ? null
                                      : listingText(context, error!)) ??
                                  listingErrorText(
                                    context,
                                    c.errorCode,
                                    c.error!,
                                  ),
                              danger: true,
                            ),
                          ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            if (step > 0 && !full)
                              marketTextAction(
                                key: const Key('market-publish-back'),
                                onPressed: c.pending
                                    ? null
                                    : () => setState(() {
                                        step -= step == 2 && manifestForm
                                            ? 2
                                            : 1;
                                        error = null;
                                      }),
                                child: Text(listingText(context, '上一步')),
                              ),
                            const Spacer(),
                            marketButtonAction(
                              key: const Key('market-publish-cancel'),
                              OutlinedButton(
                                style: tradeCancelStyle(),
                                onPressed: c.pending
                                    ? null
                                    : () => dismissStarBridgeDialog<void>(
                                        context,
                                        source:
                                            StarBridgeActivationOrigin.sourceOf(
                                              context,
                                            ),
                                      ),
                                child: Text(listingText(context, '取消')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            marketButtonAction(
                              key: const Key('market-publish-next'),
                              FilledButton(
                                style: d.side == 'buy' && !full
                                    ? tradePrimaryStyle(context).copyWith(
                                        backgroundColor: WidgetStatePropertyAll(
                                          sideColor,
                                        ),
                                      )
                                    : tradePrimaryStyle(context),
                                onPressed: c.pending
                                    ? null
                                    : () => _next(c, full),
                                child: c.pending
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox.square(
                                            dimension: 13,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.6,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(listingText(context, '正在发布…')),
                                        ],
                                      )
                                    : Text(
                                        listingText(
                                          context,
                                          full
                                            ? '管理挂单'
                                            : step == 3
                                            ? (c.error != null ? '重试' : '发布')
                                            : '下一步',
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _next(MarketplaceListingsController c, bool full) async {
    if (full) {
      dismissStarBridgeDialog<void>(
        context,
        source: StarBridgeActivationOrigin.sourceOf(context),
      );
      return;
    }
    if (step == 0 && manifestForm && d.manifestId == null) {
      setState(() => error = '请选择一个清单');
      return;
    }
    if (step == 1 && d.item['id'] == null && d.manifestId == null) {
      setState(() => error = '请选择物品');
      return;
    }
    if (step >= 2 && d.validation != null) {
      setState(() => error = d.validation);
      return;
    }
    if (step < 3) {
      setState(() {
        step += step == 0 && manifestForm ? 2 : 1;
        error = null;
      });
      return;
    }
    if (await c.write('create', d.toInput()) && mounted) {
      Navigator.pop(context);
    }
  }

  List<Widget> _typeStep(MarketplaceListingsController c) => [
    const ListingLabel('我要'),
    Row(
      children: [
        for (final (key, glyph, title, desc) in [
          ('sell', MarketplaceGlyph.sell, '出售', '把物品卖给别人'),
          ('buy', MarketplaceGlyph.buy, '求购', '收购别人的物品'),
          ('barter', MarketplaceGlyph.swap, '以物易物', '用物品换物品，不涉及 UEC'),
        ])
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: key == 'barter' ? 0 : 8),
              child: ListingOptionCard(
                glyph: glyph,
                title: listingText(context, title),
                description: listingText(context, desc),
                accent: listingSideColor(context, key),
                tintIdle: true,
                selected: d.side == key,
                onTap: () => setState(() => d.side = key),
              ),
            ),
          ),
      ],
    ),
    const SizedBox(height: 16),
    const ListingLabel('形式'),
    Row(
      children: [
        Expanded(
          child: ListingOptionCard(
            glyph: MarketplaceGlyph.inventory,
            title: listingText(context, '单件物品'),
            description: listingText(context, '一种物品，可以多件'),
            accent: listingSideColor(context, d.side),
            selected: !manifestForm,
            onTap: () => setState(() {
              manifestForm = false;
              d.manifestId = null;
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ListingOptionCard(
            glyph: MarketplaceGlyph.checklist,
            title: listingText(context, '清单'),
            description: listingText(context, '从我的清单里一次发布多件'),
            accent: listingSideColor(context, d.side),
            selected: manifestForm,
            onTap: c.manifests.isEmpty
                ? null
                : () => setState(() => manifestForm = true),
          ),
        ),
      ],
    ),
    if (manifestForm) ...[
      const SizedBox(height: 12),
      for (final r in c.manifests)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ListingPickTile(
            art: marketRows(r['items']).firstOrNull?['thumbnailUrl'] as String?,
            title: '${r['name']}',
            subtitle: listingText(context, '{n} 件物品', {
              'n': '${marketRows(r['items']).length}',
            }),
            selected: d.manifestId == r['id'],
            onTap: () => setState(() {
              d.manifestId = r['id'];
              d.item = {'name': r['name']};
            }),
          ),
        ),
    ],
  ];

  List<Widget> _itemStep(MarketplaceListingsController c) {
    return [
      ListingItemPicker(c, d, onPicked: () => setState(() {})),
      if (d.item['hasQuality'] == true) ...[
        const SizedBox(height: 6),
        const ListingLabel('品质（这件物品有制造品质）'),
        Row(
          children: [
            SizedBox(
              width: 140,
              child: TextFormField(
                initialValue: d.quality,
                keyboardType: TextInputType.number,
                decoration: listingInputDecoration(context),
                onChanged: (v) => setState(() => d.quality = v),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              listingText(context, '0～1000，按游戏内显示填写'),
              style: TextStyle(
                fontSize: 12,
                color: context.tokens.colors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    ];
  }

  Widget? _priceDelta(MarketplaceListingsController c) {
    final price = d.amount;
    if (price == null ||
        price < 0 ||
        price > 1000000000000000 ||
        d.side == 'barter') {
      return null;
    }
    final buy = d.side == 'buy';
    // A quality sell listing is compared inside its tier, never across.
    final quality = num.tryParse(d.quality.trim());
    final itemId = marketItemId(d.item);
    if (!buy && quality != null && itemId != null) {
      if (c.qualityTiers?.stale(itemId) == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) => c.ensureTiers(itemId));
      }
      final tiers = c.qualityTiers?.of(itemId);
      if (tiers == null && c.qualityTiers != null) return null;
      final tiered = marketTierPriceDelta(context, tiers: tiers, price: price, quality: quality);
      if (tiered != null) return tiered;
    }
    final best = marketNumber(buy ? d.item['highestBuy'] : d.item['best']);
    if (best == null) return null;
    final ok = buy ? price >= best : price <= best;
    final diff = (price - best).abs();
    return Text(
      ok
          ? listingText(context, buy ? '将成为当前最高收购' : '将成为当前最低卖价')
          : listingText(context, buy ? 'belowHighestBuy' : 'aboveLowestSell', {
              'diff': marketMoney(diff),
            }),
      style: TextStyle(
        fontSize: 12,
        color: ok ? MarketplacePalette.success : MarketplacePalette.warning,
      ),
    );
  }

  List<Widget> _priceStep(MarketplaceListingsController c) {
    final t = context.tokens;
    final price = d.amount;
    final qty = int.tryParse(d.quantity);
    final delta = _priceDelta(c);
    return [
      ListingPickTile(
        art: d.item['thumbnailUrl'] as String?,
        title: itemName,
        subtitle: listingText(
          context,
          {'sell': '出售', 'buy': '求购', 'barter': '以物易物'}[d.side]!,
        ),
        quality: num.tryParse(d.quality),
        selected: true,
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: t.surfaces.raised.fill,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(
              listingText(context, '市场参考'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.colors.textSecondary,
              ),
            ),
            ListingRefValue('最低卖价', _ref(d.item['best'])),
            ListingRefValue('最高收购', _ref(d.item['highestBuy'])),
            ListingRefValue('历史挂单均价', _ref(d.item['average'])),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListingLabel(d.side == 'barter' ? '想要的物品' : '单价（UEC）'),
                if (d.side == 'barter')
                  StarBridgeSelectFormField<String>(
                    identity: 'market-publish-wanted',
                    controlKey: const Key('market-publish-wanted'),
                    isDense: true,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: context.tokens.colors.textPrimary),
                    initialValue: d.wanted.isEmpty ? null : d.wanted,
                    decoration: listingInputDecoration(context),
                    items: [
                      for (final r in c.items)
                        DropdownMenuItem(
                          value: '${r['id']}',
                          child: Text('${r['name']}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => d.wanted = v!),
                  )
                else
                  TextFormField(
                    initialValue: d.price,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontFamily: t.typography.monoFamily,
                      fontSize: 15,
                    ),
                    decoration: listingInputDecoration(context),
                    onChanged: (v) => setState(() => d.price = v),
                  ),
                if (delta != null)
                  Padding(padding: const EdgeInsets.only(top: 4), child: delta),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListingLabel('数量'),
                TextFormField(
                  key: const ValueKey('publish-quantity'),
                  controller: quantityInput,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    fontFamily: t.typography.monoFamily,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                  decoration: listingInputDecoration(context).copyWith(
                    // − and + read as part of the field: no own fill, a
                    // hairline between them and the number.
                    prefixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StarBridgeNativeIconAction(
                          controlKey: const Key('market-publish-qty-dec'),
                          label: listingText(context, '减少数量'),
                          style: _stepperStyle,
                          onActivate: qty == null || qty <= 1
                              ? null
                              : (_) => adjustQuantity(qty - 1),
                          icon: const MarketplaceIcon(
                            MarketplaceGlyph.remove,
                            size: 16,
                          ),
                        ),
                        Container(width: 1, height: 18, color: t.surfaces.panel.border),
                      ],
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 1, height: 18, color: t.surfaces.panel.border),
                        StarBridgeNativeIconAction(
                          controlKey: const Key('market-publish-qty-inc'),
                          label: listingText(context, '增加数量'),
                          style: _stepperStyle,
                          onActivate: qty == null || qty >= 999999
                              ? null
                              : (_) => adjustQuantity(qty + 1),
                          icon: const MarketplaceIcon(
                            MarketplaceGlyph.add,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 32),
                    suffixIconConstraints: const BoxConstraints(minWidth: 32),
                  ),
                  onChanged: (v) => setState(() => d.quantity = v),
                ),
              ],
            ),
          ),
        ],
      ),
      if (price != null &&
          price >= 0 &&
          price <= 1000000000000000 &&
          qty != null &&
          qty >= 1 &&
          qty <= 999999 &&
          d.side != 'barter') ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              listingText(context, '合计'),
              style: TextStyle(color: t.colors.textSecondary),
            ),
            const Spacer(),
            MarketPrice(price * qty, size: 22),
          ],
        ),
      ],
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListingLabel('交易地点'),
                StarBridgeSelectFormField<String>(
                  identity: 'market-publish-location',
                  controlKey: const Key('market-publish-location'),
                  isDense: true,
                  // English labels widen the duration control beside it.
                  isExpanded: true,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: context.tokens.colors.textPrimary),
                  initialValue: d.location.isEmpty ? null : d.location,
                  decoration: listingInputDecoration(context),
                  hint: Text(
                    listingText(context, '选择地点'),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: context.tokens.colors.textSecondary),
                  ),
                  items: [
                    for (final r in c.locations)
                      DropdownMenuItem(
                        value: '${r['id']}',
                        child: Text(
                          '${r['name']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => d.location = v!),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListingLabel('有效期'),
              StarBridgeSegmentedControl<int>(
                controlKey: const Key('market-publish-days'),
                nativeStyle: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                segments: [
                  StarBridgeSegment(value: 7, label: listingText(context, '7 天')),
                  StarBridgeSegment(value: 14, label: listingText(context, '14 天')),
                  StarBridgeSegment(value: 0, label: listingText(context, '永久')),
                ],
                value: d.days,
                onChanged: (v) => setState(() => d.days = v),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            listingText(context, '交易时段'),
            style: TextStyle(fontSize: 13, color: t.colors.textSecondary),
          ),
          Text(
            c.tradeProfile != null
                ? marketTradeTime(context, c.tradeProfile!)
                : c.tradeWindow ?? listingText(context, '请到 SCM 查看或设置交易时段'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (widget.editProfile != null) ...[
            marketTextAction(
              key: const Key('market-publish-profile'),
              onPressed: widget.editProfile,
              child: Text(
                listingText(context, c.tradeProfile != null ? '修改' : '打开 SCM'),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      StarBridgeCheckboxTile(
        controlKey: const Key('market-publish-visible'),
        label: listingText(context, '发布后立即上架'),
        visualDensity: VisualDensity.compact,
        value: d.visible,
        onChanged: (v) => setState(() => d.visible = v),
        rowBuilder: (control) =>
            Row(children: [control, Text(listingText(context, '发布后立即上架'))]),
      ),
    ];
  }

  List<Widget> _confirmStep(MarketplaceListingsController c) {
    final rows = listingConfirmRows(context, c, d, itemName);
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: marketLine(context)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          children: [
            for (final (i, (label, value)) in rows.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: marketLine(context))),
                ),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.tokens.colors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (c.error == null) ...[
        const SizedBox(height: 12),
        TradeNoticeBox(listingPublishNotice(context, d)),
      ],
    ];
  }
}
