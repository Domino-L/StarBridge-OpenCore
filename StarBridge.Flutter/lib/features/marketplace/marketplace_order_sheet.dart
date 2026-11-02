import '../../design_system/icons/marketplace_icon.dart';
import 'marketplace_trade_copy.dart';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_details.dart';
import 'marketplace_order_detail.dart';
import 'marketplace_port.dart';
import 'marketplace_trade_confirm.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_widgets.dart';

Future<void> showMarketOrder(
  BuildContext context,
  MarketplaceController c,
  MarketRow row,
) async {
  final id = marketItemId(row);
  // Same suite route as the trade detail sheet: the selected open/close
  // motion, keyboard and reader closes land within two frames.
  final open = await tradeMotionDialog<bool>(
    context,
    barrierDismissible: true,
    (ctx) => Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(),
      elevation: 0,
      backgroundColor: context.tokens.surfaces.panel.fill,
      surfaceTintColor: Colors.transparent,
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height,
        width: MediaQuery.sizeOf(ctx).width < 980
            ? MediaQuery.sizeOf(ctx).width
            : 480,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      tradeText(context, '订单详情'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Spacer(),
                    StarBridgeNativeIconAction(
                      controlKey: const Key('market-order-close'),
                      label: tradeText(context, '关闭'),
                      onActivate: (source) =>
                          dismissStarBridgeDialog<bool>(ctx, source: source),
                      consumeHintEscape: false,
                      icon: MarketplaceIcon(MarketplaceGlyph.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(child: MarketOrderDetail(c, row)),
                const SizedBox(height: 12),
                if (id != null)
                  marketButtonAction(
                    OutlinedButton(
                      onPressed: () => dismissStarBridgeDialog<bool>(
                        ctx,
                        source: StarBridgeActivationOrigin.sourceOf(ctx),
                        result: true,
                      ),
                      child: Text(tradeText(context, '查看物品')),
                    ),
                    key: const Key('market-order-view-item'),
                  ),
                if (c.trades.supported &&
                    row['displayType'] != 3 &&
                    marketIsMine(row))
                  Text(marketText(context, 'mineHint'))
                else if (c.trades.supported && row['displayType'] != 3)
                  marketButtonAction(
                    FilledButton(
                      onPressed: () => confirmMarketTrade(ctx, c, row),
                      child: Text(
                        row['creatorType'] == 1
                            ? tradeText(context, '购买')
                            : tradeText(context, '出售给他'),
                      ),
                    ),
                    key: const Key('market-order-confirm'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (open == true && id != null) await c.openItem(id);
}
