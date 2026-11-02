import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_segmented_control.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_details.dart';
import 'marketplace_listing_copy.dart';
import 'marketplace_listing_errors.dart';
import 'marketplace_listings_controller.dart';
import 'marketplace_port.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_widgets.dart';

Future<void> editListing(
  BuildContext context,
  MarketplaceListingsController c,
  MarketRow row,
) => tradeMotionDialog<void>(context, (_) => _EditListingDialog(c, row));

class _EditListingDialog extends StatefulWidget {
  const _EditListingDialog(this.c, this.row);
  final MarketplaceListingsController c;
  final MarketRow row;
  @override
  State<_EditListingDialog> createState() => _EditListingState();
}

/// Owns the field controllers so they outlive the route's exit transition.
class _EditListingState extends State<_EditListingDialog> {
  MarketplaceListingsController get c => widget.c;
  MarketRow get row => widget.row;
  late final price = TextEditingController(text: '${row['price'] ?? ''}'),
      quantity = TextEditingController(text: '${row['quantity'] ?? ''}');
  late bool visible = row['visible'] == true;
  int days = 7;
  String? error;
  void update(VoidCallback change) => setState(change);

  @override
  void dispose() {
    price.dispose();
    quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (ctx, _) {
      final t = ctx.tokens;
      final ongoing = row['ongoing'] as int? ?? 0;
      Future<void> remove() async {
        final confirmed = await tradeMotionDialog<bool>(
          ctx,
          (dialog) => AlertDialog(
            title: Text(listingText(context, '删除挂单？')),
            content: Text(listingText(context, '删除后无法恢复。')),
            actions: [
              marketButtonAction(key: const Key('market-listing-delete-cancel'), TextButton(
                autofocus: true,
                onPressed: () => dismissStarBridgeDialog<bool>(
                  dialog,
                  source: StarBridgeActivationOrigin.sourceOf(dialog),
                  result: false,
                ),
                child: Text(listingText(context, '取消')),
              )),
              marketButtonAction(key: const Key('market-listing-delete-confirm'), danger: true, FilledButton(
                style: tradePrimaryStyle(dialog, danger: true),
                onPressed: () => dismissStarBridgeDialog<bool>(
                  dialog,
                  source: StarBridgeActivationOrigin.sourceOf(dialog),
                  result: true,
                ),
                child: Text(listingText(context, '删除挂单')),
              )),
            ],
          ),
        );
        if (confirmed == true &&
            await c.write('delete', {'id': row['id']}) &&
            ctx.mounted) {
          Navigator.pop(ctx);
        }
      }

      Future<void> save() async {
        final amount = num.tryParse(price.text),
            count = int.tryParse(quantity.text);
        if (amount == null ||
            !amount.isFinite ||
            amount < 0 ||
            amount > 1000000000000000 ||
            count == null ||
            count < 1 ||
            count > 999999) {
          update(() => error = listingText(context, '请核对单价和库存范围'));
          return;
        }
        if (await c.write('update', {
              'id': row['id'],
              'price': amount,
              'quantity': count,
              'expiryDays': days,
              'visible': visible,
            }) &&
            ctx.mounted) {
          Navigator.pop(ctx);
        }
      }

      void step(int delta) {
        final next = ((int.tryParse(quantity.text) ?? 1) + delta).clamp(
          1,
          999999,
        );
        quantity.text = '$next';
        update(() {});
      }

      return Dialog(
        backgroundColor: t.surfaces.floating.fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: t.surfaces.floating.border),
        ),
        child: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        listingText(context, '编辑挂单'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    StarBridgeNativeIconAction(
                      controlKey: const Key('market-listing-edit-close'),
                      label: listingText(context, '关闭'),
                      onActivate: c.pending
                          ? null
                          : (source) =>
                                dismissStarBridgeDialog<void>(ctx, source: source),
                      icon: const MarketplaceIcon(
                        MarketplaceGlyph.close,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ItemCard(row),
                if (ongoing > 0) ...[
                  const SizedBox(height: 10),
                  TradeNoticeBox(
                    listingText(context, 'editOngoing', {'n': '$ongoing'}),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label(listingText(context, '单价（UEC）')),
                          TextField(
                            autofocus: true,
                            controller: price,
                            keyboardType: TextInputType.number,
                            style: TextStyle(
                              fontFamily: t.typography.monoFamily,
                              fontSize: 15,
                            ),
                            decoration: _field(ctx),
                            onChanged: (_) => update(() {}),
                          ),
                          ?_priceHint(context, row, price.text),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Label(listingText(context, '库存')),
                        Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: t.surfaces.ground.fill,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: t.surfaces.panel.border),
                          ),
                          child: Row(
                            children: [
                              StarBridgeNativeIconAction(
                                controlKey: const Key('market-listing-qty-dec'),
                                label: listingText(context, '减少'),
                                style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
                                onActivate: (_) => step(-1),
                                icon: const MarketplaceIcon(MarketplaceGlyph.remove, size: 16),
                              ),
                              SizedBox(
                                width: 52,
                                child: TextField(
                                  controller: quantity,
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(
                                    fontFamily: t.typography.monoFamily,
                                    fontSize: 15,
                                  ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              StarBridgeNativeIconAction(
                                controlKey: const Key('market-listing-qty-inc'),
                                label: listingText(context, '增加'),
                                style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
                                onActivate: (_) => step(1),
                                icon: const MarketplaceIcon(MarketplaceGlyph.add, size: 16),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Label(listingText(context, '有效期（从现在起算）')),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StarBridgeSegmentedControl<int>(
                    controlKey: const Key('market-listing-days'),
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
                    value: days,
                    onChanged: (v) => update(() => days = v),
                  ),
                ),
                const SizedBox(height: 10),
                StarBridgeCheckboxTile(
                  controlKey: const Key('market-listing-visible'),
                  label: listingText(context, '上架'),
                  visualDensity: VisualDensity.compact,
                  value: visible,
                  onChanged: (v) => update(() => visible = v),
                  rowBuilder: (control) => Row(
                    children: [control, Text(listingText(context, '上架'))],
                  ),
                ),
                if (error != null || c.error != null) ...[
                  const SizedBox(height: 8),
                  TradeNoticeBox(
                    error ?? listingErrorText(context, c.errorCode, c.error!),
                    danger: true,
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    marketButtonAction(key: const Key('market-listing-delete'), danger: true, TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: t.colors.danger,
                      ),
                      onPressed: c.pending ? null : remove,
                      child: Text(listingText(context, '删除挂单')),
                    )),
                    const Spacer(),
                    marketButtonAction(key: const Key('market-listing-edit-cancel'), OutlinedButton(
                      style: tradeCancelStyle(),
                      onPressed: c.pending
                          ? null
                          : () => dismissStarBridgeDialog<void>(
                              ctx,
                              source: StarBridgeActivationOrigin.sourceOf(ctx),
                            ),
                      child: Text(listingText(context, '取消')),
                    )),
                    const SizedBox(width: 8),
                    marketButtonAction(key: const Key('market-listing-save'), FilledButton(
                      style: tradePrimaryStyle(ctx),
                      onPressed: c.pending ? null : save,
                      child: Text(
                        c.pending
                            ? listingText(context, '保存中…')
                            : listingText(context, '保存'),
                      ),
                    )),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Live hint: would this price become the best offer on its side?
Widget? _priceHint(BuildContext context, MarketRow row, String text) {
  final price = num.tryParse(text.replaceAll(',', ''));
  final best = marketNumber(row['best']);
  if (price == null || best == null || row['side'] == 'barter') return null;
  final buy = row['side'] == 'buy';
  final ok = buy ? price >= best : price <= best;
  return Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Text(
      ok
          ? (buy
                ? listingText(context, '将成为当前最高收购')
                : listingText(context, '将成为当前最低卖价'))
          : listingText(context, buy ? 'belowHighestBuy' : 'aboveLowestSell', {
              'diff': marketMoney((price - best).abs()),
            }),
      style: TextStyle(
        fontSize: 12,
        color: ok ? MarketplacePalette.success : MarketplacePalette.warning,
      ),
    ),
  );
}

InputDecoration _field(BuildContext context) {
  final t = context.tokens;
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: t.surfaces.ground.fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: border(t.surfaces.panel.border),
    focusedBorder: border(t.colors.accent),
    border: border(t.surfaces.panel.border),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: context.tokens.colors.textSecondary,
      ),
    ),
  );
}

class _ItemCard extends StatelessWidget {
  const _ItemCard(this.row);
  final MarketRow row;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = row['side'];
    final (label, color) = switch (side) {
      'buy' => (listingText(context, '求购'), MarketplacePalette.buyer),
      'barter' => (listingText(context, '以物易物'), t.colors.textSecondary),
      _ => (listingText(context, '出售'), t.colors.accent),
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surfaces.selected.fill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: t.colors.accent.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 40,
            child: MarketArt(
              row['thumbnailUrl'] as String?,
              category: marketCategoryOf(row),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 11, color: color),
                      ),
                    ),
                    if (row['quality'] != null)
                      MarketQualityBadge({
                        'qualityData': {
                          'type': 'material',
                          'quality': row['quality'],
                        },
                      }, prefixed: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
