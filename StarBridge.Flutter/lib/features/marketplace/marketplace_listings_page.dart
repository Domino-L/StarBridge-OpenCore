import 'marketplace_listing_components.dart';
import 'marketplace_numbers.dart';
import 'marketplace_time.dart';
import '../../design_system/icons/marketplace_icon.dart';
import 'marketplace_listing_copy.dart';
import 'marketplace_listing_errors.dart';
import 'marketplace_recovery.dart';
import 'marketplace_listing_editor.dart';
import 'marketplace_listing_duplicate.dart';
import 'marketplace_listing_publish.dart';
export 'marketplace_listing_publish.dart' show ListingPublishDialog;

import 'dart:async';

import 'package:flutter/material.dart';
import 'marketplace_activity_rail.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_listings_controller.dart';
import 'marketplace_listings_batch.dart';
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

class _ListingsState extends State<MarketplaceListingsPage> with MarketListingBatch {
  @override
  final selected = <Object?>{};
  String side = 'all';
  late bool manifests = widget.initialManifests;
  @override
  MarketplaceListingsController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.refresh();
  }

  @override
  String name(MarketRow r) =>
      r['name'] as String? ?? listingText(context, '名称待更新');
  Future<void> publish([MarketRow? row]) async {
    if (c.pending || c.writeUncertain || row != null && !listingCanCopy(row, c.fullOrders)) return;
    final generation = c.fullOrders?.port.generation;
    final draft = row == null ? ListingDraft() : await duplicateListing(row, c.fullOrders);
    if (!mounted || generation != c.fullOrders?.port.generation) return;
    await tradeMotionDialog<void>(
      context,
      (_) => ListingPublishDialog(
        c,
        draft,
        initialStep: row == null ? 0 : 2,
        initialError: row != null && draft.side == 'barter' && draft.wanted.isEmpty
            ? '没有读到想要的物品，请重新选择' : null,
        editProfile: widget.editProfile,
      ),
    );
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
        onSelected: (v) {
          setState(() => side = v);
          unawaited(c.loadRemaining());
        },
        segments: {
          'all': listingText(context, '全部'),
          'sell': listingText(context, '出售'),
          'buy': listingText(context, '求购'),
          'barter': listingText(context, '以物易物'),
        },
      );
      final publishButton = FilledButton.icon(
        style: tradePrimaryStyle(context),
        onPressed: (c.pending || c.writeUncertain) ? null : publish,
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
                  ListingCapacity(used: c.activeSingleListingCount, limit: c.limit),
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
                    ListingCapacity(used: c.activeSingleListingCount, limit: c.limit),
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
          if (marketplaceNeedsLogin(c.errorCode)) MarketplaceAuthNotice(c.errorCode, login: c.login),
          if (c.writeUncertain) Text(recoveryText(context, '请先刷新核对上次操作结果，再编辑或发布挂单')),
          if (c.writeUncertain) marketTextAction(key: const Key('market-listings-confirm-readback'),
            onPressed: c.loading ? null : c.inspectUncertainWrite,
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
                      value: list.isNotEmpty && list.every((r) => selected.contains(r['id'])),
                      mixed: list.any((r) => selected.contains(r['id'])) &&
                          !list.every((r) => selected.contains(r['id'])),
                      onChanged: (c.pending || c.writeUncertain || !c.allListingsLoaded)
                          ? null
                          : (_) => setState(() {
                              if (list.every((r) => selected.contains(r['id']))) {
                                selected.removeAll(list.map((r) => r['id']));
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
                      (c.pending || c.writeUncertain) ? null : () => batch(true),
                    ),
                    ListingBatchButton(
                      listingText(context, '下架'),
                      MarketplaceGlyph.hidden,
                      (c.pending || c.writeUncertain) ? null : () => batch(false),
                    ),
                    if (!c.rows.any((r) => selected.contains(r['id']) && marketIsChecklist(r))) ListingBatchButton(
                      listingText(context, '复制为新挂单'),
                      MarketplaceGlyph.copy,
                      (c.pending || c.writeUncertain) || selected.length != 1
                          ? null
                          : () => publish(
                              c.rows.firstWhere(
                                (r) => selected.contains(r['id']),
                              ),
                            ),
                    ),
                    marketTextAction(
                      key: const Key('market-listings-clear-selection'),
                      onPressed: (c.pending || c.writeUncertain)
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
                ? c.manifests.isEmpty
                    ? Center(child: Text(listingText(context, c.loading ? '正在读取清单…' : '还没有清单，请先在 SCM 创建')))
                    : GridView.builder(
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
                              overflow: fadeOverflow(context),
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
                                ?scmLocalTime(r['updated']),
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
                              onPressed: (c.pending || c.writeUncertain) ? null : () {
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
                : c.rows.isEmpty && !c.loading && c.error == null
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(listingText(context, '还没有挂单，发布一条试试吧。')),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: (c.pending || c.writeUncertain) ? null : publish,
                      child: Text(listingText(context, '发布挂单'))),
                  ]))
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
                                  listingText(context, '已显示 {x} / {y}', {
                                    'x': '${c.rows.length}', 'y': '${c.total ?? '—'}',
                                  }),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }
                            final r = list[i],
                                on = selected.contains(list[i]['id']);
                            final best = c.listingBestPrice(r),
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
                                    onChanged: (c.pending || c.writeUncertain)
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
                                      marketListingImage(r),
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
                                            if (!marketIsChecklist(r) && marketQuality(r) != null)
                                              MarketQualityBadge(
                                                r,
                                                prefixed: true,
                                              )
                                            else if (!marketIsChecklist(r) && r['quality'] != null)
                                              MarketQualityBadge({
                                                'qualityData': {
                                                  'type': 'material',
                                                  'quality': r['quality'],
                                                },
                                              }, prefixed: true),
                                            if (r['hasOngoingTransactions'] == true)
                                              ListingTag(
                                                listingText(
                                                  context,
                                                  '有进行中的交易',
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
                                          marketTextAction(
                                            key: ValueKey<(String, Object?)>(('market-listing-detail', r['id'])),
                                            onPressed: c.openOrder == null ? null : () async {
                                              await c.openOrder!(context, r);
                                              if (mounted) setState(() {});
                                            },
                                            child: Text(listingText(context, '以物易物 · 看详情')),
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
                                              onEdit: (c.pending || c.writeUncertain)
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
                                              scmPermanent(r['expiry'])
                                                  ? listingText(context, '永久')
                                                  : scmLocalTime(r['expiry']) ?? '—',
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
                                    onActivate: (c.pending || c.writeUncertain)
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
                                    enabled: !(c.pending || c.writeUncertain),
                                    entries: [
                                      for (final (id, label, run) in [
                                        if (listingCanCopy(r, c.fullOrders)) ('copy', listingText(context, '复制为新挂单'), () => publish(r)),
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
                                          onActivate: (c.pending || c.writeUncertain) ? null : (source) => unawaited(
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
                                          onActivate: (c.pending || c.writeUncertain) ? null : toggle,
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

