import 'package:flutter/widgets.dart';
import 'marketplace_copy.dart';

const _copy = <String, List<String>>{
  'quantityMissing': ['可交易数量没读到，选多了可能被 SCM 拒绝', '可交易數量未讀到，選多了可能被 SCM 拒絕', 'Tradable quantity unavailable. SCM may reject a larger quantity.'],
  'available': ['可交易', '可交易', 'Tradable'],
  'myQuality': ['我的品质（求购要求上限）', '我的品質（求購要求上限）', 'My quality (maximum buy requirement)'],
  'buyCeiling': ['只看要求不高于 {n} 的求购', '只看要求不高於 {n} 的求購', 'Buy orders requiring no more than {n}'],
  'loadedOnly': ['仅筛选已读取的订单', '僅篩選已讀取的訂單', 'Filters loaded orders only'],
  'loadedMatches': ['已读取 {n} 条，符合条件 {m} 条', '已讀取 {n} 條，符合條件 {m} 條', '{n} loaded, {m} matching'],
  'tierLowest': ['同档最低卖价', '同檔最低賣價', 'Lowest ask in this tier'],
  'sameTierPrice': ['与同档最低卖价相同', '與同檔最低賣價相同', 'Equal to the lowest ask in this tier'],
  'tierOthers': ['同档其他报价', '同檔其他報價', 'Other offers in this tier'],
  'noBundleSort': ['SCM 不支持按套价筛选和排序', 'SCM 不支援按套價篩選和排序', 'SCM does not support filtering or sorting by bundle price'],
  'singleOnly': ['只对单件有效', '只對單件有效', 'Single items only'],
  'bundleSumHint': ['这张清单有数量大于 1 的物品。SCM 目前按各行价格直接相加算每套价格，没有乘数量；成交价以 SCM 交易单上的为准。', '這張清單有數量大於 1 的物品。SCM 目前按各行價格直接相加算每套價格，沒有乘數量；成交價以 SCM 交易單上的為準。', 'This bundle has items with a quantity above 1. SCM currently adds up the line prices for the price per bundle, without multiplying by quantity; the deal price is the one on the SCM trade.'],
  'bundlePublishHint': ['清单里有数量大于 1 的物品。发布后 SCM 会按各行价格直接相加显示每套价格，没有乘数量，和这里的合计会不一样。', '清單裡有數量大於 1 的物品。發佈後 SCM 會按各行價格直接相加顯示每套價格，沒有乘數量，和這裡的合計會不一樣。', 'This bundle has items with a quantity above 1. After publishing, SCM will show the price per bundle as the line prices added up, without multiplying by quantity, so it will differ from the total here.'],
  'loadedBundleSort': ['已读取清单按每套价格排序', '已讀取清單按每套價格排序', 'Loaded bundles sorted by price per bundle'],
};

String marketDisplayText(BuildContext context, String key, {Object? n, Object? matched}) {
  final locale = marketLocale(context);
  return _copy[key]![locale == 'en' ? 2 : locale == 'hant' ? 1 : 0]
      .replaceAll('{n}', '$n').replaceAll('{m}', '$matched');
}
