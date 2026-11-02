import 'package:flutter/material.dart';
import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_widgets.dart';
import 'marketplace_details.dart';
import 'marketplace_listing_copy.dart';
import 'marketplace_listings_controller.dart';
const listingStepNames = ['类型', '物品', '价格与数量', '确认'];

/// The review step's label and value rows, in the reader's language.
List<(String, String)> listingConfirmRows(
  BuildContext context,
  MarketplaceListingsController c,
  ListingDraft d,
  String itemName,
) {
  String l(String key, [Map<String, String> args = const {}]) =>
      listingText(context, key, args);
  final price = d.amount;
  final qty = int.tryParse(d.quantity);
  final location = c.locations
      .where((r) => '${r['id']}' == d.location)
      .firstOrNull?['name'];
  final wanted = c.items.where((r) => '${r['id']}' == d.wanted).firstOrNull;
  final side = {'sell': '出售', 'buy': '求购', 'barter': '以物易物'}[d.side]!;
  return [
    (l('类型'), '${l(side)} · ${l(d.manifestId == null ? '单件物品' : '清单')}'),
    (
      l('物品'),
      '$itemName${d.quality.isEmpty ? '' : ' · ${l('品质 {n}', {'n': d.quality})}'}',
    ),
    if (d.side == 'barter') ...[
      (l('想换'), '${wanted?['name'] ?? d.wanted}'),
      (l('数量'), d.quantity),
    ] else ...[
      (l('单价 × 数量'), '${marketMoney(price)} × ${d.quantity}'),
      if (price != null && qty != null)
        (l('合计'), '${marketMoney(price * qty)} UEC'),
    ],
    (l('地点'), '${location ?? l('未选择')}'),
    (l('有效期'), d.days == 0 ? l('永久') : l('{n} 天', {'n': '${d.days}'})),
    (
      l('交易时段'),
      c.tradeProfile != null
          ? marketTradeTime(context, c.tradeProfile!)
          : c.tradeWindow ?? l('请到 SCM 查看或设置交易时段'),
    ),
    (l('发布后'), l(d.visible ? '立即上架' : '先不上架')),
  ];
}

/// What happens after publishing, by side and visibility.
String listingPublishNotice(BuildContext context, ListingDraft d) => listingText(
  context,
  !d.visible
      ? '发布后先不上架，可在“我的挂单”中上架。'
      : d.side == 'buy'
      ? '发布后会出现在市场里，卖家响应后你会在“待我处理”里确认是否同意。'
      : d.side == 'barter'
      ? '发布后会出现在市场里，交换请求可在“我的交易”中查看。'
      : '发布后会出现在市场里，买家发起交易后你会在“待我处理”里看到。',
);

/// The side's cue color, matching the 出售 / 求购 / 以物易物 tags in 我的挂单.
Color listingSideColor(BuildContext context, String side) => switch (side) {
  'buy' => MarketplacePalette.buyer,
  'barter' => context.tokens.colors.textSecondary,
  _ => context.tokens.colors.accent,
};

InputDecoration listingInputDecoration(
  BuildContext context, {
  String? hint,
  Widget? prefix,
}) {
  final t = context.tokens;
  // Same corner and weight as the wizard's segmented controls (有效期), on a
  // light raised fill rather than a dark well, so fields sit in the dialog.
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: t.colors.textSecondary),
    prefixIcon: prefix == null
        ? null
        : Padding(padding: const EdgeInsets.all(10), child: prefix),
    prefixIconConstraints: const BoxConstraints(minWidth: 38),
    filled: true,
    fillColor: Color.alphaBlend(
      t.colors.textPrimary.withValues(alpha: .035),
      t.surfaces.raised.fill,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    enabledBorder: border(t.surfaces.panel.border),
    focusedBorder: border(t.colors.accent),
    border: border(t.surfaces.panel.border),
  );
}

class ListingWizardSteps extends StatelessWidget {
  const ListingWizardSteps(this.step, {super.key, this.color});
  final int step;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = color ?? t.colors.accent;
    return Semantics(
      label: listingText(context, '第 {n} 步，共 4 步，{name}', {
        'n': '${step + 1}',
        'name': listingText(context, listingStepNames[step]),
      }),
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: t.surfaces.panel.border,
                ),
              ),
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < step ? accent : Colors.transparent,
                border: Border.all(
                  width: 1.5,
                  color: i <= step ? accent : t.surfaces.panel.border,
                ),
              ),
              child: i < step
                  ? MarketplaceIcon(MarketplaceGlyph.check, size: 12, color: t.colors.onAccent)
                  : Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontFamily: t.typography.monoFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: i == step
                            ? accent
                            : t.colors.textSecondary,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Text(
              listingText(context, listingStepNames[i]),
              style: TextStyle(
                fontSize: 12,
                fontWeight: i == step ? FontWeight.w600 : FontWeight.w400,
                color: i <= step
                    ? t.colors.textPrimary
                    : t.colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ListingLabel extends StatelessWidget {
  const ListingLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      listingText(context, text),
      style: TextStyle(
        fontSize: 12,
        color: context.tokens.colors.textSecondary,
      ),
    ),
  );
}

class ListingRefValue extends StatelessWidget {
  const ListingRefValue(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final unknown = value == listingText(context, '暂无');
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${listingText(context, label)} '),
          TextSpan(
            text: value,
            style: TextStyle(
              fontFamily: unknown ? null : t.typography.monoFamily,
              fontWeight: unknown ? FontWeight.w400 : FontWeight.w600,
              color: unknown ? t.colors.textSecondary : t.colors.textPrimary,
            ),
          ),
        ],
      ),
      style: TextStyle(fontSize: 12, color: t.colors.textSecondary),
    );
  }
}

class ListingOptionCard extends StatelessWidget {
  const ListingOptionCard({
    super.key,
    required this.title,
    required this.description,
    required this.selected,
    required this.glyph,
    this.onTap,
    this.accent,
    this.tintIdle = false,
  });
  final MarketplaceGlyph glyph;
  final String title, description;
  final bool selected;
  final VoidCallback? onTap;
  /// Cue color for this option (for example the side it publishes); defaults to accent.
  final Color? accent;
  /// Show the accent on the icon even when not selected (each side shows its own color).
  final bool tintIdle;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tint = accent ?? t.colors.accent;
    final color = selected || tintIdle ? tint : t.colors.textSecondary;
    final card = Material(
        color: selected
            ? (accent == null ? t.surfaces.selected.fill : tint.withValues(alpha: .12))
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: selected ? tint : t.surfaces.panel.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: _target(onTap, selected, Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarketplaceIcon(glyph, size: 20, color: color),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: t.colors.textSecondary,
                  ),
                ),
              ],
            ),
          )),
      );
    return onTap == null
        ? Semantics(selected: selected, button: true, child: card)
        : card;
  }
}

class ListingPickTile extends StatelessWidget {
  const ListingPickTile({
    super.key,
    required this.art,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
    this.quality,
  });
  final String? art;
  final String title, subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final num? quality;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tile = Material(
        color: selected ? t.surfaces.selected.fill : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: selected
                ? t.colors.accent.withValues(alpha: .55)
                : t.surfaces.panel.border,
          ),
        ),
        child: _target(onTap, selected, Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox.square(dimension: 40, child: MarketArt(art)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 12,
                          color: t.colors.textSecondary,
                        ),
                      ),
                      if (quality != null)
                        MarketQualityBadge({
                          'qualityData': {
                            'type': 'material',
                            'quality': quality,
                          },
                        }, prefixed: true),
                    ],
                  ),
                ),
                if (selected && onTap != null)
                  MarketplaceIcon(MarketplaceGlyph.confirmedFilled, size: 20, color: t.colors.accent),
              ],
            ),
          )),
      );
    return onTap == null
        ? Semantics(selected: selected, child: tile)
        : tile;
  }
}

/// The selectable target for a card/tile. Without onTap the content stays as
/// it was (the native InkWell was inert too); with it, the suite row target.
Widget _target(VoidCallback? onTap, bool selected, Widget content) =>
    onTap == null
        ? content
        : StarBridgeActionRow(
            inheritContentStyle: true,
            semanticSelected: selected,
            baseRadius: 9,
            onActivate: (_, _) => onTap(),
            child: content,
          );
