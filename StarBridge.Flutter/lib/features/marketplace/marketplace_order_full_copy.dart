import 'package:flutter/widgets.dart';
import 'marketplace_copy.dart';

const _copy = <String, List<String>>{
  'loading': ['读取中…', '讀取中…', 'Loading…'],
  'incomplete': ['清单内容没有读全', '清單內容沒有讀全', 'The full contents have not been loaded'],
  'missing': ['没有读到', '沒有讀到', 'Could not load'],
  'retry': ['重试', '重試', 'Retry'],
  'blocked': [
    '没有读到这张清单的全部物品，暂时不能下单',
    '沒有讀到這張清單的全部物品，暫時不能下單',
    'All items in this bundle could not be loaded. You cannot place this order yet.',
  ],
};

String orderFullText(BuildContext context, String key) {
  final locale = marketLocale(context);
  return _copy[key]![locale == 'en' ? 2 : locale == 'hant' ? 1 : 0];
}
