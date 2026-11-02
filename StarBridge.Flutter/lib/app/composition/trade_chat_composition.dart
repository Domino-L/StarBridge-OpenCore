import 'package:flutter/widgets.dart';

import '../../design_system/appearance/appearance_scope.dart';
import '../../features/marketplace/marketplace_chat_controller.dart';
import '../../features/marketplace/marketplace_trade_chat_view.dart';
import '../../shared/trade_chat_slot.dart';

/// 0.7.2 G9: offers 交易消息 to the messages page (and any page below).
Widget withTradeChat(MarketplaceChatController? chat, Widget child) =>
    chat == null
    ? child
    : TradeChatSlot(
        unread: chat.unreadValue,
        requests: chat.requests,
        build: (context, header) => HolidayColorExempt(
          child: MarketplaceTradeChatView(
            chat,
            header: header,
            recentOrders: chat.recentOrders,
          ),
        ),
        child: child,
      );
