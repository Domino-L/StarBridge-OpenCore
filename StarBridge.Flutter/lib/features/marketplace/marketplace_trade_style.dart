import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/icons/marketplace_icon.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';
import 'marketplace_port.dart';
import 'marketplace_trade_copy.dart';
import 'marketplace_widgets.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

ButtonStyle tradePrimaryStyle(BuildContext context, {bool danger = false}) =>
    FilledButton.styleFrom(
      minimumSize: const Size(88, 40),
      backgroundColor: danger
          ? Theme.of(context).colorScheme.error
          : context.tokens.colors.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
ButtonStyle tradeCancelStyle() => OutlinedButton.styleFrom(
  minimumSize: const Size(72, 40),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
);

class TradeMiniCard extends StatelessWidget {
  const TradeMiniCard(this.row, {super.key});
  final MarketRow row;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox.square(dimension: 48, child: MarketArt.of(row)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tradeItemName(context, row),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              [
                if (row['number'] != null) '×${row['number']}',
                if (row['amount'] != null)
                  tradeText(context, 'miniTotal', {
                    'amount': marketMoney(row['amount']),
                  }),
                if (row['counterpartyName'] != null)
                  '${row['actorRole'] == 'seller' ? tradeText(context, '买家') : tradeText(context, '卖家')} ${row['counterpartyName']}',
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
    ],
  );
}

class TradeNoticeBox extends StatelessWidget {
  const TradeNoticeBox(
    this.text, {
    this.danger = false,
    this.warning = false,
    super.key,
  });
  final String text;
  final bool danger, warning;
  @override
  Widget build(BuildContext context) {
    final tone = danger
        ? Theme.of(context).colorScheme.error
        : warning
        ? MarketplacePalette.warning
        : context.tokens.colors.accent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .09),
        border: Border.all(color: tone.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarketplaceIcon(
            danger || warning
                ? MarketplaceGlyph.warning
                : MarketplaceGlyph.info,
            size: 16,
            color: tone,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.tokens.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showTradeSuccess(
  BuildContext context, {
  required String message,
  required VoidCallback open,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final colors = context.tokens.colors;
  messenger.hideCurrentSnackBar();
  messenger.showOnly(
    starBridgeSnackBarFromContext(
      context,
      starBridgeTimedSnackBar(
        behavior: SnackBarBehavior.floating,
        width: MediaQuery.sizeOf(context).width < 592
            ? MediaQuery.sizeOf(context).width - 32
            : 560,
        backgroundColor: context.tokens.surfaces.floating.fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.textSecondary.withValues(alpha: .2)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        content: Row(
          children: [
            const MarketplaceIcon(
              MarketplaceGlyph.confirmed,
              color: MarketplacePalette.success,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
              ),
            ),
            marketTextAction(
              key: const Key('market-success-view'),
              onPressed: () {
                messenger.hideCurrentSnackBar();
                open();
              },
              child: Text(tradeText(context, '查看交易单')),
            ),
            StarBridgeIconAction(
              key: const Key('market-success-close'),
              label: tradeText(context, '关闭'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onActivate: (_) => messenger.hideCurrentSnackBar(),
              icon: MarketplaceIcon(
                MarketplaceGlyph.close,
                size: 18,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      tone: ActionTone.success,
    ),
  );
}
