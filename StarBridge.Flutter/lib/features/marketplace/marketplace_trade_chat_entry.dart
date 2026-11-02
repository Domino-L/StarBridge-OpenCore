import 'package:flutter/material.dart';

import 'marketplace_chat_controller.dart';
import 'marketplace_controller.dart';
import 'marketplace_port.dart';
import 'marketplace_trade_chat_copy.dart';
import 'marketplace_widgets.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

/// 交易单「私信对方」 / 订单详情「联系卖家」 (0.7.2 G9): open the conversation in
/// 好友与私信 · 交易消息, with this order attached to the composer.
const tradeChatEntryCopy = <String, List<String>>{
  '私信对方': ['私信对方', '私訊對方', 'Message them'],
  '联系卖家': ['联系卖家', '聯絡賣家', 'Contact seller'],
  '联系买家': ['联系买家', '聯絡買家', 'Contact buyer'],
  '暂时打不开会话，请稍后再试。': [
    '暂时打不开会话，请稍后再试。',
    '暫時無法開啟對話，請稍後再試。',
    'Could not open the conversation. Try again shortly.',
  ],
};

MarketChatAttachment? tradeChatAttachment(MarketRow row) {
  final id = (row['orderId'] as num?)?.toInt() ?? (row['id'] as num?)?.toInt();
  if (id == null || id <= 0) return null;
  final name = row['itemsName'] ?? row['productName'] ?? row['name'] ?? '';
  final number = row['transactionNumber'] ?? row['orderNumber'];
  return MarketChatAttachment(
    id,
    [
      '$name ×${row['number'] ?? row['quantity'] ?? 1}',
      if (number != null) '#$number',
    ].join(' · '),
  );
}

/// From a trade: the Host already gave the counterparty's chat reference.
Future<void> messageTradeCounterparty(
  BuildContext sheet,
  MarketplaceController c,
  MarketRow trade,
) async {
  final chat = c.tradeChat, reference = trade['counterpartyChat'];
  if (chat == null || reference is! String) return;
  chat.requestOpen(reference, attach: tradeChatAttachment(trade));
  await Navigator.of(sheet).maybePop();
  c.openDestination?.call('/messages');
}

/// From an order: the Host looks the seller up by order number.
Future<void> contactOrderOwner(
  BuildContext context,
  MarketplaceController c,
  MarketRow order,
) async {
  final chat = c.tradeChat, number = order['orderNumber'];
  if (chat == null || number is! String) return;
  final opened = await chat.openOrder(
    number,
    attach: tradeChatAttachment(order),
  );
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.maybeOf(context)?.showOnly(
      starBridgeTimedSnackBar(content: Text(_entryText(context, '暂时打不开会话，请稍后再试。'))),
    );
    return;
  }
  await Navigator.of(context).maybePop();
  c.openDestination?.call('/messages');
}

String tradeChatEntryText(BuildContext context, String key) =>
    _entryText(context, key);

String _entryText(BuildContext context, String key) {
  final values = tradeChatEntryCopy[key];
  if (values == null) return chatText(context, key);
  final locale = Localizations.localeOf(context);
  return locale.languageCode != 'zh'
      ? values[2]
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? values[1]
      : values[0];
}
