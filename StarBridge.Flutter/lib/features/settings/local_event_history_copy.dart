import 'package:flutter/widgets.dart';

String localHistoryText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final value = _copy[key] ?? _copy['readFailed']!;
  if (locale.languageCode == 'en') return value.$3;
  if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') {
    return value.$2;
  }
  return value.$1;
}

const _copy = <String, (String, String, String)>{
  'newEvents': ('有新记录，点击刷新', '有新記錄，點擊重新整理', 'New records — refresh to view'),
  'stale': ('刷新未完成，保留上次读取的记录。请重试。', '重新整理未完成，保留上次讀取的記錄。請重試。', 'Refresh failed. Previous records are still shown. Try again.'),
  'title': ('本地事件日志', '本機事件記錄', 'Local event history'),
  'scope': ('本机已保存的历史记录', '本機已儲存的歷史記錄', 'History saved on this computer'),
  'category': ('类别', '類別', 'Category'),
  'all': ('全部', '全部', 'All'),
  'session': ('会话', '工作階段', 'Session'),
  'identity': ('身份', '身分', 'Identity'),
  'server': ('服务器', '伺服器', 'Server'),
  'ship': ('舰船', '艦船', 'Ship'),
  'location': ('地点', '地點', 'Location'),
  'life': ('生命状态', '生命狀態', 'Life status'),
  'other': ('其他', '其他', 'Other'),
  'refresh': ('刷新', '重新整理', 'Refresh'),
  'previous': ('上一页', '上一頁', 'Previous'),
  'next': ('下一页', '下一頁', 'Next'),
  'close': ('关闭', '關閉', 'Close'),
  'loading': ('正在读取…', '正在讀取…', 'Loading…'),
  'readFailed': (
    '暂时无法读取，请重试。',
    '暫時無法讀取，請重試。',
    'Could not load history. Try again.',
  ),
  'empty': ('没有已保存的记录', '沒有已儲存的記錄', 'No saved records'),
  'filteredEmpty': ('此类别没有记录', '此類別沒有記錄', 'No records in this category'),
  'recovered': (
    '正在显示备份中的记录，原文件未改动。',
    '正在顯示備份中的記錄，原檔案未更動。',
    'Showing backup records. The original file is unchanged.',
  ),
  'unavailable': (
    '无法读取记录，原文件已保留。',
    '無法讀取記錄，原檔案已保留。',
    'Could not read the records. The original file is preserved.',
  ),
  'changed': (
    '记录已变化，已返回第一页。',
    '記錄已變更，已返回第一頁。',
    'History changed. Returned to the first page.',
  ),
  'export': ('导出', '匯出', 'Export'),
  'clear': ('清空', '清空', 'Clear'),
  'notAvailable': ('暂不可用', '暫不可用', 'Not available yet'),
};
