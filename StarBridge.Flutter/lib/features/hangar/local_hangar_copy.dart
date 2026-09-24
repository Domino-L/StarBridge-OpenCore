import 'package:flutter/material.dart';

import '../../shared/ships/ship_reviewed_display.dart';

/// Copy for the current account's local hangar, independent of the reader.
class LocalHangarCopy {
  LocalHangarCopy(BuildContext context)
    : locale = Localizations.localeOf(context);

  final Locale locale;
  String pick(String cn, String tw, String en) => locale.languageCode != 'zh'
      ? en
      : locale.scriptCode == 'Hant' ||
            const {'TW', 'HK', 'MO'}.contains(locale.countryCode)
      ? tw
      : cn;

  String get title => pick('个人机库', '個人機庫', 'Personal hangar');
  String get currentOwned => pick('当前拥有', '目前擁有', 'Currently owned');
  String get formerlyOwned => pick('曾拥有', '曾擁有', 'Previously owned');
  String get removedAt => pick('最后移出机库', '最後移出機庫', 'Last removed from hangar');
  String get formerEmpty =>
      pick('暂无曾拥有的舰船', '暫無曾擁有的艦船', 'No previously owned ships');
  String get formerHint => pick(
    '已不再拥有的舰船型号会保留在这里，仍可选为最爱舰船。同型号只显示一条。',
    '已不再擁有的艦船型號會保留在這裡，仍可選為最愛艦船。同型號只顯示一筆。',
    'Models you no longer own stay here and can still be selected as favorites. Each model appears once.',
  );
  String get legacySource => pick(
    '正在显示旧账号已同步的舰船；重新读取 RSI 机库后可保存到本机。',
    '正在顯示舊帳號已同步的艦船；重新讀取 RSI 機庫後可儲存到本機。',
    'Showing ships synced by your old account. Read your RSI hangar to save an updated copy on this device.',
  );
  String get summary => pick('机库摘要', '機庫摘要', 'Hangar overview');
  String get shipsLabel => pick('舰船数量', '艦船數量', 'Ships');
  String get valueLabel => pick('机库估值', '機庫估值', 'Estimated value');
  String get knownValue => pick('已知估值', '已知估值', 'Known value');
  String get noPrice => pick('暂无价格', '暫無價格', 'Price unavailable');
  String get priceBasis =>
      pick('历史目录参考价 · USD', '歷史目錄參考價 · USD', 'Historical catalog prices · USD');
  String unpriced(int n) =>
      pick('$n 艘未计价', '$n 艘未計價', '$n ${n == 1 ? 'ship' : 'ships'} unpriced');
  String get delivery => pick('交付状态', '交付狀態', 'Delivery status');
  String get roleDistribution => pick('用途分布', '用途分布', 'Role distribution');
  String get unknown => pick('未知', '未知', 'Unknown');
  String get categoryLabel => pick('用途', '用途', 'Role');
  String category(String? value) {
    final label = shipCategoryLabels[value];
    if (label != null) return pick(label.$1, label.$2, label.$3);
    return switch (value) {
      'combat' => pick('战斗', '戰鬥', 'Combat'),
      'transport' => pick('运输', '運輸', 'Transport'),
      'industrial' => pick('工业', '工業', 'Industrial'),
      'exploration' => pick('探索', '探索', 'Exploration'),
      'support' => pick('支援', '支援', 'Support'),
      'utility' => pick('通用', '通用', 'Utility'),
      _ => unknown,
    };
  }

  String status(String? value) => switch (value) {
    'flyable' => pick('可飞', '可飛', 'Flyable'),
    'concept' => pick('概念', '概念', 'Concept'),
    _ => unknown,
  };
  String get priceLabel => pick('目录价格', '目錄價格', 'Catalog price');
  String get imageUnavailable => pick('暂无图片', '暫無圖片', 'No image');
  String usd(num value) {
    final fixed = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
    final parts = fixed.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    return '\$$whole${parts.length > 1 ? '.${parts.last}' : ''}';
  }

  String get read => pick('读取机库', '讀取機庫', 'Read hangar');
  String get refresh => pick('刷新列表', '重新整理清單', 'Refresh list');
  String get retry => pick('重试', '重試', 'Retry');
  String get search =>
      pick('搜索名称或制造商', '搜尋名稱或製造商', 'Search names or manufacturers');
  String get clearSearch => pick('清除搜索', '清除搜尋', 'Clear search');
  String get noMatches => pick('没有符合条件的舰船', '沒有符合條件的艦船', 'No matching ships');
  String get searchHint =>
      pick('试试其他名称或制造商。', '試試其他名稱或製造商。', 'Try another name or manufacturer.');
  String get readFailure => pick(
    '暂时无法读取本机机库，请重试。',
    '暫時無法讀取本機機庫，請重試。',
    'Cannot read your local hangar right now. Try again.',
  );
  String get saved => pick('保存在本机', '儲存在本機', 'Saved on this device');
  String get partial => pick(
    '部分物品类别待核对，已识别舰船已保存；原有舰船暂不移除。',
    '部分物品類別待核對，已識別艦船已儲存；原有艦船暫不移除。',
    'Some item types need review. Recognized ships were saved; existing ships were not removed.',
  );
  String count(int count) =>
      pick('$count 艘舰船', '$count 艘艦船', count == 1 ? '1 ship' : '$count ships');
  String get original => pick('原名', '原名', 'Original name');
  String get manufacturer => pick('制造商', '製造商', 'Manufacturer');
  String get addedAt => pick('加入时间', '加入時間', 'Date added');
  String get close => pick('关闭', '關閉', 'Close');
  String? combatSize(String? value) {
    final label = shipGroundSizeLabels[value];
    if (label != null) return pick(label.$1, label.$2, label.$3);
    return switch (value) {
      'small' => pick('小型', '小型', 'Small'),
      'medium' => pick('中型', '中型', 'Medium'),
      'large' => pick('大型', '大型', 'Large'),
      'capital' => pick('旗舰级', '旗艦級', 'Capital'),
      _ => null,
    };
  }

  String savedOn(BuildContext context, DateTime? date) =>
      date == null ? saved : '$saved · ${dateTime(context, date)}';
  String dateTime(BuildContext context, DateTime date) {
    final local = date.toLocal();
    final material = MaterialLocalizations.of(context);
    return '${material.formatCompactDate(local)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
  }

  String get loading =>
      pick('正在读取本机机库…', '正在讀取本機機庫…', 'Loading your local hangar…');
  String get noSaved => pick('尚未保存机库', '尚未儲存機庫', 'No saved hangar yet');
  String get emptySaved =>
      pick('机库中还没有舰船', '機庫中還沒有艦船', 'No ships in your hangar yet');
  String get emptyHint => pick(
    '读取 RSI 机库，核对后保存到本机。',
    '讀取 RSI 機庫，核對後儲存到本機。',
    'Read your RSI hangar, review the ships, then save them on this device.',
  );
}
