import 'hangar_reader_copy.dart';

class HangarInventoryCopy extends HangarReaderCopy {
  HangarInventoryCopy(super.context);
  String get testTitle => pick('测试机库', '測試機庫', 'Test hangar');
  String get isolation => pick(
    '测试环境 · 仅保存到本机测试库',
    '測試環境 · 僅儲存到本機測試庫',
    'Test environment · Saved only to the local test database',
  );
  String get testData => pick('预览测试数据', '預覽測試資料', 'Preview test data');
  String get savedList => pick('已保存机库', '已儲存機庫', 'Saved hangar');
  String get changes => pick('核对本次变更', '核對本次變更', 'Review changes');
  String get save => pick('确认保存', '確認儲存', 'Confirm save');
  String get discard => pick('放弃预览', '放棄預覽', 'Discard preview');
  String get search => pick('搜索舰船名称', '搜尋艦船名稱', 'Search ship names');
  String get refresh => pick('重新读取', '重新讀取', 'Refresh');
  String get check => pick('查询保存结果', '查詢儲存結果', 'Check save result');
  String get details => pick('舰船详情', '艦船詳情', 'Ship details');
  String get close => pick('关闭', '關閉', 'Close');
  String get noSaved => pick(
    '尚未保存机库。先预览测试数据，再确认保存。',
    '尚未儲存機庫。先預覽測試資料，再確認儲存。',
    'No saved hangar. Preview test data, then confirm save.',
  );
  String get emptySaved =>
      pick('已保存的机库为空。', '已儲存的機庫為空。', 'Your saved hangar is empty.');
  String get noMatches => pick(
    '没有符合条件的舰船。试试其他名称或分类。',
    '沒有符合條件的艦船。試試其他名稱或分類。',
    'No matching ships. Try another name or category.',
  );
  String scenario(String value) => switch (value) {
    'basic' => pick('基础清单 · 3 艘', '基礎清單 · 3 艘', 'Basic list · 3 ships'),
    'expanded' => pick('扩展清单 · 6 艘', '擴充清單 · 6 艘', 'Expanded list · 6 ships'),
    _ => pick('空清单', '空清單', 'Empty list'),
  };
  String size(String value) => switch (value) {
    'unknown' => pick('未分类', '未分類', 'Unclassified'),
    'small' => pick('小型', '小型', 'Small'),
    'medium' => pick('中型', '中型', 'Medium'),
    'large' => pick('大型', '大型', 'Large'),
    'capital' => pick('旗舰级', '旗艦級', 'Capital'),
    _ => pick('全部分类', '全部分類', 'All sizes'),
  };
  String diff(int added, int removed, int retained) => pick(
    '新增 $added · 移除 $removed · 保留 $retained',
    '新增 $added · 移除 $removed · 保留 $retained',
    'Add $added · Remove $removed · Keep $retained',
  );
  String state(String phase) => switch (phase) {
    'loading' => pick('正在读取…', '正在讀取…', 'Loading…'),
    'previewing' => pick('正在准备预览…', '正在準備預覽…', 'Preparing preview…'),
    'saving' => pick('正在保存…', '正在儲存…', 'Saving…'),
    'checking' => pick('正在查询保存结果…', '正在查詢儲存結果…', 'Checking save result…'),
    'uncertain' => pick(
      '尚未确认保存结果，请查询后继续。',
      '尚未確認儲存結果，請查詢後繼續。',
      'Save result is not confirmed. Check before continuing.',
    ),
    'saved' => pick('已保存', '已儲存', 'Saved'),
    'preview' => notSaved,
    _ => savedList,
  };
  String failure(String code) => switch (code) {
    'conflict' => pick(
      '机库已发生变化。放弃本次预览，重新读取后再试。',
      '機庫已發生變化。放棄本次預覽，重新讀取後再試。',
      'Hangar changed. Discard this preview, refresh, and try again.',
    ),
    'expired' => pick(
      '预览已过期，请重新预览。',
      '預覽已過期，請重新預覽。',
      'Preview expired. Create a new preview.',
    ),
    'ambiguous' => pick(
      '有舰船需要核对，暂时无法保存。',
      '有艦船需要核對，暫時無法儲存。',
      'Some ships need review before saving.',
    ),
    'empty_confirmation' => pick(
      '请先确认移除全部已保存舰船。',
      '請先確認移除全部已儲存艦船。',
      'Confirm removal of all saved ships first.',
    ),
    _ => pick(
      '暂时无法连接机库服务，请重试。',
      '暫時無法連線機庫服務，請重試。',
      'Cannot reach the hangar service. Try again.',
    ),
  };
  String get clearConfirm => pick(
    '确认移除机库中全部已保存舰船',
    '確認移除機庫中全部已儲存艦船',
    'Remove all ships from the saved hangar',
  );
}
