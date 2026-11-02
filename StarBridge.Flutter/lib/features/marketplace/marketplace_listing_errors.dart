import 'package:flutter/widgets.dart';
import 'marketplace_copy.dart';
import 'marketplace_listing_copy.dart';
import 'marketplace_trades_controller.dart';
import 'marketplace_trade_copy.dart';
import 'marketplace_port.dart';

String listingErrorText(BuildContext context, String? code, String fallback) {
  final values = listingErrors[code];
  if (values != null) {
    final locale = marketLocale(context);
    return values[locale == 'en' ? 2 : locale == 'hant' ? 1 : 0];
  }
  if (code != null) return tradeText(context, tradeError(MarketplaceTradeError(code)));
  return listingText(context, fallback);
}

const listingErrors = <String, List<String>>{
  'marketplace.forbidden': ['SCM 拒绝了这次操作；一直这样请联系支持。', 'SCM 拒絕了這次操作；一直這樣請聯絡支援。', 'SCM refused this action. If it keeps happening, contact support.'],
  'marketplace.listing_limit': ['挂单已满，请先删除不需要的挂单。', '掛單已滿，請先刪除不需要的掛單。', 'Listing limit reached. Delete listings you no longer need.'],
  'marketplace.listing_same_item_limit': ['同一物品最多发布 3 条挂单。', '同一物品最多發布 3 條掛單。', 'You can publish up to 3 listings for the same item.'],
  'marketplace.listing_manifest_limit': ['清单挂单最多 5 条。', '清單掛單最多 5 條。', 'You can publish up to 5 checklist listings.'],
  'marketplace.listing_item_invalid': ['物品已不可用，请重新选择。', '物品已不可用，請重新選擇。', 'This item is unavailable. Select another item.'],
  'marketplace.listing_invalid': ['请核对物品、单价、数量、品质和地点。', '請核對物品、單價、數量、品質和地點。', 'Check the items, price, quantity, quality and location.'],
  'marketplace.listing_has_ongoing': ['有进行中的交易，暂时不能删除挂单。', '有進行中的交易，暫時不能刪除掛單。', 'This listing has ongoing trades and cannot be deleted yet.'],
  'marketplace.listing_cannot_publish': ['库存不足或已有交易占用库存，暂时不能上架。', '庫存不足或已有交易佔用庫存，暫時不能上架。', 'Stock is insufficient or reserved by ongoing trades. This listing cannot be published.'],
  'marketplace.listing_quantity_below_ongoing': ['库存不能低于进行中的交易所需数量。', '庫存不能低於進行中的交易所需數量。', 'Stock cannot be lower than the quantity needed by ongoing trades.'],
  'marketplace.checklist_invalid': ['请核对清单数量及物品：每份清单需 2–50 件不重复物品。', '請核對清單數量及物品：每份清單需 2–50 件不重複物品。', 'Check checklist limits and items. Each checklist needs 2–50 distinct items.'],
  'marketplace.template_limit': ['模板数量已达上限，请先删除不需要的模板。', '範本數量已達上限，請先刪除不需要的範本。', 'Template limit reached. Delete templates you no longer need.'],
  'marketplace.template_system': ['系统模板不能修改或删除。', '系統範本不能修改或刪除。', 'System templates cannot be edited or deleted.'],
  'marketplace.not_owner': ['这条挂单或清单不属于当前账号。', '這條掛單或清單不屬於目前帳號。', 'This listing or checklist does not belong to the current account.'],
  // CX-T15: an unknown SCM refusal code arrives as trade_rejected on every write.
  'marketplace.trade_rejected': ['SCM 未接受此操作，请刷新后核对挂单。', 'SCM 未接受此操作，請重新整理後核對掛單。', 'SCM rejected this action. Refresh and check your listings.'],
  'marketplace.listing_rejected': ['SCM 未接受此操作，请刷新后核对挂单。', 'SCM 未接受此操作，請重新整理後核對掛單。', 'SCM rejected this action. Refresh and check your listings.'],
};
