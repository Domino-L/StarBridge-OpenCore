import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/icons/marketplace_icon.dart';
import 'marketplace_listing_copy.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_listings_controller.dart';
import 'marketplace_port.dart';
import 'marketplace_surfaces.dart';
import 'marketplace_widgets.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_listings_page.dart';

mixin MarketListingBatch on State<MarketplaceListingsPage> {
  MarketplaceListingsController get c;
  Set<Object?> get selected;
  String name(MarketRow row);

  Future<void> batch(bool visible) async {
    final result = await c.setVisibility(
      c.rows.where((r) => selected.contains(r['id'])).toList(),
      visible,
    );
    if (!mounted || result.isEmpty) return;
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
                              '${result.where((r) => r['state'] == 'uncertain').length}',
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
                                          : listingText(context, {
                                              'rejected': '被拒绝',
                                              'skipped': '未执行',
                                            }[r['state']] ?? '未确认，请刷新核对'),
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

}
