import 'package:flutter/widgets.dart';

import 'marketplace_copy.dart';

const marketBundleCopy = <String, List<String>>{
  '看清单': ['看清单', '看清單', 'View checklist'],
  '看详情': ['看详情', '看詳情', 'View details'],
  '每套价格': ['每套价格', '每套價格', 'Price per set'],
  '套': ['套', '套', 'sets'],
  '件': ['件', '件', 'pcs'],
  '等 {n} 件': ['等 {n} 件', '等 {n} 件', 'and {n} more items'],
  '交易方式': ['交易方式', '交易方式', 'Trade type'],
  '未填写': ['未填写', '未填寫', 'Not specified'],
  '以物易物需要和对方商量，请先私信联系': [
    '以物易物需要和对方商量，请先私信联系',
    '以物易物需要和對方商量，請先私訊聯絡',
    'Barter needs to be agreed with the other trader. Send them a message first.',
  ],
};

String bundleText(BuildContext context, String key,
    [Map<String, String> args = const {}]) {
  final locale = marketLocale(context);
  var text = marketBundleCopy[key]![locale == 'en' ? 2 : locale == 'hant' ? 1 : 0];
  for (final entry in args.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value);
  }
  return text;
}
