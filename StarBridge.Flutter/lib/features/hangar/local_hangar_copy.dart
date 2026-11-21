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

  String get deviceStorage => pick(
    '机库只保存在这台电脑上。',
    '機庫只儲存在這台電腦上。',
    'Your hangar is saved on this computer only.',
  );
  // User 11-05 final copy: "保存到你的账号就行 因为是SCM登录".
  String get accountStorage => pick(
    '机库已保存到你的账号。',
    '機庫已儲存到你的帳號。',
    'Your hangar is saved to your account.',
  );
  String get cloudFirstUpload => pick(
    '机库已保存到你的账号。舰队和组织能看到哪些舰船，仍然按你的共享设置；个人页访客能看到什么，按个人页的公开范围和模块。',
    '機庫已儲存到你的帳號。艦隊和組織能看到哪些艦船，仍然依你的分享設定；個人頁訪客能看到什麼，依個人頁的公開範圍和模組。',
    "Your hangar is saved to your account. What fleets and organizations can see still follows your sharing settings; what profile visitors can see follows your profile's visibility and modules.",
  );
  String cloudRestored(int count) => pick(
    '已载入你账号里的机库（$count 艘）。',
    '已載入你帳號裡的機庫（$count 艘）。',
    'Loaded the hangar saved to your account ($count ships).',
  );
  String get title => pick('个人机库', '個人機庫', 'Personal hangar');
  String get currentOwned => pick('当前拥有', '目前擁有', 'Currently owned');
  String get favorites => pick('收藏', '收藏', 'Bookmarks');
  String get favorite => pick('收藏舰船', '收藏艦船', 'Bookmark ship');
  String get updatingFavorite =>
      pick('正在更新收藏…', '正在更新收藏…', 'Updating bookmark…');
  String get unfavorite => pick('取消收藏', '取消收藏', 'Remove bookmark');
  String get favoriteFailure => pick(
    '未能确认收藏结果，请刷新机库后重试。',
    '未能確認收藏結果，請重新整理機庫後重試。',
    'Bookmark could not be confirmed. Refresh your hangar and try again.',
  );
  String get gridView => pick('大图', '大圖', 'Large');
  String get compactView => pick('紧凑', '緊湊', 'Compact');
  String get listView => pick('列表', '清單', 'List');
  String get segmentLabel => pick('分段', '分段', 'Group');
  String get bySize => pick('按尺寸', '按尺寸', 'By size');
  String get byMaker => pick('按制造商', '按製造商', 'By maker');
  String get jumpLabel => pick('跳转', '跳轉', 'Jump to');
  String get backToTop => pick('回到顶部', '回到頂部', 'Back to top');
  String get searchAction => pick('搜索', '搜尋', 'Search');
  String get otherSection => pick('其他', '其他', 'Other');
  String shipUnits(int n) =>
      pick('$n 艘', '$n 艘', n == 1 ? '1 ship' : '$n ships');
  String get backToWall => pick('返回整墙', '返回整牆', 'Back to wall');
  String stagePosition(String section, int index, int count) => pick(
    '$section · 第 $index / $count 艘',
    '$section · 第 $index / $count 艘',
    '$section · $index of $count',
  );
  String instanceShort(int index) =>
      pick('第 $index 艘', '第 $index 艘', 'No. $index');
  String get previousShip => pick('上一艘', '上一艘', 'Previous ship');
  String get nextShip => pick('下一艘', '下一艘', 'Next ship');
  String get viewDetails => pick('查看详情', '查看詳情', 'View details');
  String get bookmarked => pick('已收藏', '已收藏', 'Bookmarked');
  String get officialStatus => pick('官网状态', '官網狀態', 'Official status');
  String get roleFact => pick('定位', '定位', 'Role');
  String get allRoles => pick('全部用途', '全部用途', 'All roles');
  String get sortLabel => pick('排序', '排序', 'Sort');
  String get sortDefault => pick('默认顺序', '預設順序', 'Default order');
  String get sortName => pick('名称', '名稱', 'Name');
  String get sortAdded => pick('最近入库', '最近入庫', 'Recently acquired');
  String get sortValue => pick('参考价格', '參考價格', 'Reference price');
  String get clearFilters => pick('清除筛选', '清除篩選', 'Clear filters');
  String get details => pick('舰船详情', '艦船詳情', 'Ship details');
  String get thisShip => pick('本艘', '本艘', 'Your ship');
  String get allSizes => pick('全部尺寸', '全部尺寸', 'All sizes');
  String get refreshing => pick('正在刷新列表…', '正在重新整理清單…', 'Refreshing list…');
  String instance(int index, int count) => pick(
    '同型号第 $index / $count 艘',
    '同型號第 $index / $count 艘',
    'Ship $index of $count of this model',
  );
  String get expandDetails => pick('展开详情', '展開詳情', 'Expand details');
  String get compactDetails => pick('收起详情', '收起詳情', 'Compact details');
  String get sameModel =>
      pick('同型号多艘', '同型號多艘', 'Multiple ships of this model');
  String get formerlyOwned => pick('曾拥有', '曾擁有', 'Previously owned');
  String get removedAt => pick('最后移出机库', '最後移出機庫', 'Last removed from hangar');
  String get formerEmpty =>
      pick('暂无曾拥有的舰船', '暫無曾擁有的艦船', 'No previously owned ships');
  String get formerHint => pick(
    '每艘移出机库的舰船都会单独保留在这里，图片和收藏会保留，仍可选为最爱舰船。',
    '每艘移出機庫的艦船都會單獨保留在這裡，圖片和收藏會保留，仍可選為最愛艦船。',
    'Each ship that leaves your hangar stays here with its image and bookmark. You can still choose it as a profile favorite.',
  );
  String get formerBookmarksHint => pick(
    '这里显示你已收藏、但不再拥有的舰船。',
    '這裡顯示你已收藏、但不再擁有的艦船。',
    'Showing bookmarked ships you no longer own.',
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
  String get sizeLabel => pick('尺寸', '尺寸', 'Size');
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
  String get search => pick(
    '搜索昵称、型号、备注或制造商',
    '搜尋暱稱、型號、備註或製造商',
    'Search nickname, model, notes or manufacturer',
  );
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

  /// Official RSI pledge date; unknown reads "入库时间 未知" in details.
  String get acquiredOn => pick('入库时间', '入庫時間', 'Acquired');
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

  String savedOn(BuildContext context, DateTime? date) => date == null
      ? saved
      : '${pick('从 RSI 读取保存于', '從 RSI 讀取儲存於', 'RSI hangar saved')} ${dateTime(context, date)}';
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
