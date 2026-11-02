import 'package:flutter/widgets.dart';

import 'marketplace_copy.dart' show marketLocale;

/// 走势页 copy (layout A, user 2026-10-28): Simplified, Traditional, English.
String trendText(BuildContext context, String key, {Object? n}) {
  final values = _trendCopy[key];
  if (values == null) return key;
  final locale = marketLocale(context);
  final text =
      values[locale == 'en'
          ? 2
          : locale == 'hant'
          ? 1
          : 0];
  return n == null ? text : text.replaceAll('{n}', '$n');
}

const _trendCopy = <String, List<String>>{
  'title': ['价格走势', '價格走勢', 'Price history'],
  'sell': ['出售挂单均价', '出售掛單均價', 'Average sell listing'],
  'buy': ['求购挂单均价', '求購掛單均價', 'Average buy listing'],
  'noBuyInRange': ['这段时间没有求购', '這段時間沒有求購', 'No buy listings in this range'],
  'unit': ['单位 UEC', '單位 UEC', 'Unit: UEC'],
  'days': ['{n} 天', '{n} 天', '{n} days'],
  'now': ['当前出售均价', '目前出售均價', 'Current sell average'],
  'change': ['{n} 天涨跌', '{n} 天漲跌', '{n}-day change'],
  'low': ['{n} 天最低', '{n} 天最低', '{n}-day low'],
  'high': ['{n} 天最高', '{n} 天最高', '{n}-day high'],
  'avg': ['{n} 天均价', '{n} 天均價', '{n}-day average'],
  'daily': ['每日明细', '每日明細', 'Daily detail'],
  'recent': ['最近 {n} 天', '最近 {n} 天', 'Last {n} days'],
  'date': ['日期', '日期', 'Date'],
  'sellShort': ['出售均价', '出售均價', 'Sell avg.'],
  'buyShort': ['求购均价', '求購均價', 'Buy avg.'],
  'vsPrev': ['较前一天', '較前一天', 'vs. previous day'],
  'flat': ['持平', '持平', 'Flat'],
  'noSell': ['无出售', '無出售', 'No sell'],
  'noBuy': ['无求购', '無求購', 'No buy'],
  'daySell': ['当天无出售', '當天無出售', 'No sell that day'],
  'dayBuy': ['当天无求购', '當天無求購', 'No buy that day'],
  'all': ['查看全部 {n} 天', '查看全部 {n} 天', 'Show all {n} days'],
  'less': ['收起', '收起', 'Show less'],
  'note': [
    '每天 SCM 挂单价格的均价，不是实时成交价。',
    '每天 SCM 掛單價格的均價，不是即時成交價。',
    'Daily averages of SCM listing prices, not live trades.',
  ],
};
