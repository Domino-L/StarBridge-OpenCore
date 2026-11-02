import 'marketplace_listing_components.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/icons/marketplace_icon.dart';
import 'marketplace_listing_copy.dart';
import 'marketplace_listing_errors.dart';
import 'marketplace_listing_editor.dart';
import 'marketplace_listing_publish.dart';
export 'marketplace_listing_publish.dart' show ListingPublishDialog;

import 'dart:async';

import 'package:flutter/material.dart';
import 'marketplace_activity_rail.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_listings_controller.dart';
import 'marketplace_port.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_widgets.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_details.dart';

/// Explicitly injected data only; production composition does not register a fixture port.
class MarketplaceListingsPage extends StatefulWidget {
  const MarketplaceListingsPage(
    this.controller, {
    this.openTrades,
    this.editProfile,
    this.initialManifests = false,
    this.moreTabs = const {},
    this.openTab,
    this.railed = false,
    super.key,
  });
  final MarketplaceListingsController controller;

  /// Inside 我的交易's rail (layout A): the rail picks 挂单 / 清单, so the
  /// page shows one row, its title and filters, and no repeated heading.
  final bool railed;
  final bool initialManifests;
  final VoidCallback? openTrades, editProfile;

  /// Further 我的交易 sub-tabs after 清单 (评价, 举报与拉黑), opened by key.
  final Map<String, String> moreTabs;
  final ValueChanged<String>? openTab;
  @override
  State<MarketplaceListingsPage> createState() => _ListingsState();
}

class _ListingsState extends State<MarketplaceListingsPage> {
  final selected = <Object?>{};
  String side = 'all';
  late bool manifests = widget.initialManifests;
  MarketplaceListingsController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.refresh();
  }

  String name(MarketRow r) =>
      r['name'] as String? ?? listingText(context, '名称待更新');
  Future<void> publish([MarketRow? row]) async {
    final draft = ListingDraft(
      item: row == null ? const {} : {'id': row['itemId'], 'name': row['name']},
      side: row?['side'] as String? ?? 'sell',
      price: '${row?['price'] ?? ''}',
      quantity: '${row?['quantity'] ?? 1}',
      location: row?['location'] as String? ?? '',
      quality: '${row?['quality'] ?? ''}',
      wanted: row?['wanted'] as String? ?? '',
    );
    await tradeMotionDialog<void>(
      context,
      (_) => ListingPublishDialog(
        c,
        draft,
        initialStep: row == null ? 0 : 2,
        editProfile: widget.editProfile,
      ),
    );
  }

  Future<void> batch(bool visible) async {
    final result = await c.setVisibility(
      c.rows.where((r) => selected.contains(r['id'])).toList(),
      visible,
    );
    if (!mounted) return;
    final ordered = [
      ...result.where((r) => r['success'] == true),
      ...result.where((r) => r['success'] != true),
    ];
    await tradeMotionDialog<void>(
      context,
      (ctx) => Dialog(
        backgroundColor: ctx.tokens.surfaces.floating.fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: ctx.tokens.surfaces.floating.border),
        ),
        child: SizedBox(
          width: 460,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 14, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        visible
                            ? listingText(context, '批量上架结果')
                            : listingText(context, '批量下架结果'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    StarBridgeNativeIconAction(
                      controlKey: const Key('market-listing-batch-close'),
                      label: listingText(context, '关闭'),
                      onActivate: (source) =>
                          dismissStarBridgeDialog<void>(ctx, source: source),
                      icon: const MarketplaceIcon(
                        MarketplaceGlyph.close,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TradeNoticeBox(
                        listingText(context, 'batchSummary', {
                          'ok':
                              '${result.where((r) => r['success'] == true).length}',
                          'pending':
                              '${result.where((r) => r['success'] != true).length}',
                        }),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: ctx.tokens.surfaces.raised.fill,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Column(
                          children: [
                            for (final (i, r) in ordered.indexed)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  border: i == 0
                                      ? null
                                      : Border(
                                          top: BorderSide(
                                            color: marketLine(ctx),
                                          ),
                                        ),
                                ),
                                child: Row(
                                  children: [
                                    MarketplaceIcon(
                                      r['success'] == true
                                          ? MarketplaceGlyph.confirmed
                                          : MarketplaceGlyph.failed,
                                      size: 16,
                                      color: r['success'] == true
                                          ? MarketplacePalette.success
                                          : ctx.tokens.colors.danger,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        name(r),
                                        maxLines: 1,
                                        overflow: TextOverflow.fade,
                                        softWrap: false,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      r['success'] == true
                                          ? (visible
                                                ? listingText(context, '已上架')
                                                : listingText(context, '已下架'))
                                          : listingText(context, '未确认，请刷新核对'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: r['success'] == true
                                            ? ctx.tokens.colors.textSecondary
                                            : ctx.tokens.colors.danger,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerRight,
                        child: marketButtonAction(FilledButton(
                          autofocus: true,
                          style: tradePrimaryStyle(ctx),
                          onPressed: () => dismissStarBridgeDialog<void>(
                            ctx,
                            source: StarBridgeActivationOrigin.sourceOf(ctx),
                          ),
                          child: Text(listingText(context, '知道了')),
                        ), key: const Key('market-listing-batch-ok')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(selected.clear);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final list = c.rows
          .where((r) => side == 'all' || r['side'] == side)
          .toList();
      final sideFilter = ListingSegments<String>(
        selected: side,
        onSelected: (v) => setState(() => side = v),
        segments: {
          'all': listingText(context, '全部'),
          'sell': listingText(context, '出售'),
          'buy': listingText(context, '求购'),
          'barter': listingText(context, '以物易物'),
        },
      );
      final publishButton = FilledButton.icon(
        style: tradePrimaryStyle(context),
        onPressed: c.pending ? null : publish,
        icon: const MarketplaceIcon(MarketplaceGlyph.add, size: 16),
        label: Text(listingText(context, '发布挂单')),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.railed)
            MarketSectionBar(
              manifests
                  ? listingText(context, '清单')
                  : listingText(context, '挂单'),
              filters: [if (!manifests) sideFilter],
              actions: [
                if (!manifests) ...[
                  ListingCapacity(used: c.rows.length, limit: c.limit),
                  publishButton,
                ],
              ],
            )
          else ...[
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  ListingSegments<String>(
                    selected: manifests ? 'lists' : 'listings',
                    onSelected: (v) => v == 'trades'
                        ? widget.openTrades?.call()
                        : widget.moreTabs.containsKey(v)
                        ? widget.openTab?.call(v)
                        : setState(() => manifests = v == 'lists'),
                    segments: {
                      if (widget.openTrades != null)
                        'trades': listingText(context, '交易'),
                      'listings':
                          '${listingText(context, '挂单')} ${c.rows.length}',
                      'lists': listingText(context, '清单'),
                      ...widget.moreTabs,
                    },
                  ),
                  if (!manifests) sideFilter,
                ],
              ),
              if (!manifests)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListingCapacity(used: c.rows.length, limit: c.limit),
                    const SizedBox(width: 14),
                    publishButton,
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          MarketHeading(
            manifests
                ? listingText(context, '我的清单')
                : listingText(context, '我的挂单'),
          ),
          const SizedBox(height: 12),
          ],
          if (c.error != null) MarketNotice(listingErrorText(context, c.errorCode, c.error!), retry: c.refresh),
          if (c.writeUncertain) marketTextAction(key: const Key('market-listings-confirm-readback'),
            onPressed: c.confirmReadBack,
            child: Text(listingText(context, '已核对，继续操作'))),
          if (c.loading) const LinearProgressIndicator(),
          if (selected.isNotEmpty && !manifests)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: context.tokens.surfaces.selected.fill,
                  border: Border.all(
                    color: context.tokens.colors.accent.withValues(alpha: .4),
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    StarBridgeCheckboxTile(
                      controlKey: const Key('market-listings-select-all'),
                      label: listingText(context, '全选'),
                      rowBuilder: (control) => control,
                      visualDensity: VisualDensity.compact,
                      compactTarget: true,
                      value: selected.length == list.length,
                      mixed: selected.isNotEmpty && selected.length != list.length,
                      onChanged: c.pending
                          ? null
                          : (_) => setState(() {
                              if (selected.length == list.length) {
                                selected.clear();
                              } else {
                                selected.addAll(list.map((r) => r['id']));
                              }
                            }),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      listingText(context, 'selectedCount', {
                        'n': '${selected.length}',
                      }),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    ListingBatchButton(
                      listingText(context, '上架'),
                      MarketplaceGlyph.visible,
                      c.pending ? null : () => batch(true),
                    ),
                    ListingBatchButton(
                      listingText(context, '下架'),
                      MarketplaceGlyph.hidden,
                      c.pending ? null : () => batch(false),
                    ),
                    ListingBatchButton(
                      listingText(context, '复制为新挂单'),
                      MarketplaceGlyph.copy,
                      c.pending || selected.length != 1
                          ? null
                          : () => publish(
                              c.rows.firstWhere(
                                (r) => selected.contains(r['id']),
                              ),
                            ),
                    ),
                    marketTextAction(
                      key: const Key('market-listings-clear-selection'),
                      onPressed: c.pending
                          ? null
                          : () => setState(selected.clear),
                      child: Text(
                        listingText(context, '取消选择'),
                        style: TextStyle(
                          color: context.tokens.colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: manifests
                ? GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 340,
                          mainAxisExtent: 220,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                    itemCount: c.manifests.length,
                    itemBuilder: (context, i) {
                      final r = c.manifests[i];
                      return MarketSurface(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                for (final item in marketRows(
                                  r['items'],
                                ).take(3))
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: SizedBox.square(
                                      dimension: 60,
                                      child: MarketArt(
                                        item['thumbnailUrl'] as String?,
                                        category: marketCategoryOf(item),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              name(r),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                listingText(context, 'itemCount', {
                                  'n': '${marketRows(r['items']).length}',
                                }),
                                if (r['updated'] != null) '${r['updated']}',
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.tokens.colors.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            marketButtonAction(OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                foregroundColor:
                                    context.tokens.colors.textPrimary,
                                side: BorderSide(
                                  color: context.tokens.surfaces.panel.border,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              onPressed: () {
                                // Made once: the route may rebuild its builder.
                                final draft = ListingDraft(
                                  manifestId: r['id'],
                                  item: {'name': name(r)},
                                );
                                tradeMotionDialog<void>(
                                  context,
                                  (_) => ListingPublishDialog(
                                    c,
                                    draft,
                                    initialStep: 2,
                                    editProfile: widget.editProfile,
                                  ),
                                );
                              },
                              child: Text(listingText(context, '用清单发布')),
                            ), key: ValueKey(('market-manifest-publish', r['id']))),
                          ],
                        ),
                      );
                    },
                  )
                : MarketSurface(
                    corners: false,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final narrow = box.maxWidth < 850;
                        return ListView.separated(
                          itemCount: list.length + 2,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: marketLine(context)),
                          itemBuilder: (context, i) {
                            if (i == 0) return ListingListHeader(narrow: narrow);
                            i -= 1;
                            if (i == list.length) {
                              return Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  c.loading
                                      ? listingText(context, '正在读取…')
                                      : listingText(context, 'shownAll', {
                                          'n': '${list.length}',
                                        }),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }
                            final r = list[i],
                                on = selected.contains(list[i]['id']);
                            final best = marketNumber(r['best']),
                                price = marketNumber(r['price']);
                            final optimal =
                                best != null &&
                                price != null &&
                                (r['side'] == 'buy'
                                    ? price >= best
                                    : price <= best);
                            return Container(
                              decoration: BoxDecoration(
                                color: on
                                    ? context.tokens.colors.accent.withValues(
                                        alpha: .06,
                                      )
                                    : null,
                                border: Border(
                                  left: BorderSide(
                                    width: 3,
                                    color: on
                                        ? context.tokens.colors.accent
                                        : Colors.transparent,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  StarBridgeCheckboxTile(
                                    controlKey: ValueKey(('market-listing-select', r['id'])),
                                    label: name(r),
                                    rowBuilder: (control) => control,
                                    value: on,
                                    onChanged: c.pending
                                        ? null
                                        : (v) => setState(() {
                                            v
                                                ? selected.add(r['id'])
                                                : selected.remove(r['id']);
                                          }),
                                  ),
                                  SizedBox.square(
                                    dimension: 44,
                                    child: MarketArt(
                                      r['thumbnailUrl'] as String?,
                                      category: marketCategoryOf(r),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name(r),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            ListingSideTag(r['side'] as String?),
                                            if (marketQuality(r) != null)
                                              MarketQualityBadge(
                                                r,
                                                prefixed: true,
                                              )
                                            else if (r['quality'] != null)
                                              MarketQualityBadge({
                                                'qualityData': {
                                                  'type': 'material',
                                                  'quality': r['quality'],
                                                },
                                              }, prefixed: true),
                                            if ((r['ongoing'] as int? ?? 0) > 0)
                                              ListingTag(
                                                listingText(
                                                  context,
                                                  'ongoingCount',
                                                  {'n': '${r['ongoing']}'},
                                                ),
                                                context.tokens.colors.accent,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (r['side'] == 'barter')
                                          Text(
                                            '${listingText(context, '想换')} ${r['wanted'] ?? listingText(context, '待更新')}',
                                          )
                                        else
                                          MarketPrice(price),
                                        if (best != null && price != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 3,
                                            ),
                                            child: ListingPriceHint(
                                              optimal: optimal,
                                              text: optimal
                                                  ? listingText(
                                                      context,
                                                      '当前最优价',
                                                    )
                                                  : narrow
                                                  ? null
                                                  : '${r['side'] == 'buy' ? listingText(context, '最高收购') : listingText(context, '最低卖价')} ${marketMoney(best)} · ',
                                              onEdit: c.pending
                                                  ? null
                                                  : () => editListing(
                                                      context,
                                                      c,
                                                      r,
                                                    ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      '${r['quantity'] ?? listingText(context, '待更新')}',
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  SizedBox(
                                    width: narrow ? 68 : 100,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ListingListingStatus(r),
                                        if (!narrow && r['expiry'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 3,
                                            ),
                                            child: Text(
                                              '${r['expiry']}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: context
                                                    .tokens
                                                    .colors
                                                    .textSecondary,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  StarBridgeNativeIconAction(
                                    controlKey: ValueKey(('market-listing-edit', r['id'])),
                                    label: listingText(context, '编辑'),
                                    onActivate: c.pending
                                        ? null
                                        : (_) => editListing(context, c, r),
                                    icon: const MarketplaceIcon(
                                      MarketplaceGlyph.edit,
                                      size: 16,
                                    ),
                                  ),
                                  Semantics(container: true, child: StarBridgeMenuAnchor(
                                    semanticLabel: listingText(context, '更多'),
                                    consumeOutsideTaps: true,
                                    enabled: !c.pending,
                                    entries: [
                                      for (final (id, label, run) in [
                                        ('copy', listingText(context, '复制为新挂单'), () => publish(r)),
                                        (
                                          'visibility',
                                          r['visible'] == true
                                              ? listingText(context, '下架')
                                              : listingText(context, '上架'),
                                          () => c.write('visibility', {
                                            'id': r['id'],
                                            'visible': r['visible'] != true,
                                          }),
                                        ),
                                      ])
                                        StarBridgeMenuEntry(
                                          id: ('market-listing-$id', r['id']),
                                          controlKey: ValueKey(('market-listing-$id', r['id'])),
                                          label: label,
                                          onActivate: c.pending ? null : (source) => unawaited(
                                            runStarBridgeActivation<void>(source, () async => run()),
                                          ),
                                          // Native PopupMenuItem: 112 x 48 with 12 inset.
                                          child: SizedBox(
                                            width: 88,
                                            height: 48,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(label,
                                                style: Theme.of(context).textTheme.labelLarge),
                                            ),
                                          ),
                                        ),
                                    ],
                                    builder: (context, controller, focus, toggle) =>
                                        StarBridgeNativeIconAction(
                                          key: ValueKey(('market-listing-more', r['id'])),
                                          label: listingText(context, '更多'),
                                          focusNode: focus,
                                          onActivate: c.pending ? null : toggle,
                                          icon: MarketplaceIcon(MarketplaceGlyph.more),
                                        ),
                                  )),
                                ],
                              ),
                            );
                          },
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

