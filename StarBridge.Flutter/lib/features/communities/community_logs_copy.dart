import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

const communityLogsCopy = <String, (String, String, String)>{
  'title': ('组织日志', '組織日誌', 'Organization log'),
  'All': ('全部', '全部', 'All'),
  '成员': ('成员', '成員', 'Members'),
  '公告': ('公告', '公告', 'Announcements'),
  '舰队': ('组织', '組織', 'Organization'),
  'search': ('搜索日志', '搜尋日誌', 'Search logs'),
  'reload': ('重新读取', '重新讀取', 'Reload'),
  'close': ('关闭', '關閉', 'Close'),
  'previous': ('上一页', '上一頁', 'Previous'),
  'next': ('下一页', '下一頁', 'Next'),
  'delete': ('删除日志', '刪除日誌', 'Delete log entry'),
  'keep': ('保留日志', '保留日誌', 'Keep entry'),
  'confirm': ('删除这条日志？', '刪除這條日誌？', 'Delete this log entry?'),
  'consequence': (
    '会删除这条记录及其合并的重复记录，无法在应用内恢复。不撤销日志记录的业务操作。',
    '會刪除這條記錄及其合併的重複記錄，無法在應用程式內復原。不撤銷日誌記錄的業務操作。',
    'This removes the entry and its grouped repetitions. It cannot be restored in the app. The recorded action is not undone.',
  ),
  'empty': ('暂无组织日志', '暫無組織日誌', 'No organization logs yet'),
  'noMatches': (
    '没有符合条件的日志，请调整分类或搜索词。',
    '沒有符合條件的日誌，請調整分類或搜尋詞。',
    'No matching logs. Change the category or search terms.',
  ),
  'unknownTime': ('时间未知', '時間未知', 'Time unknown'),
  'repeated': ('累计 {count} 次', '累計 {count} 次', '{count} occurrences'),
  'page': (
    '{start}–{end} / {total} 条',
    '{start}–{end} / {total} 條',
    '{start}–{end} of {total} entries',
  ),
  'deleted': ('日志已删除', '日誌已刪除', 'Log entry deleted'),
  'outcomeUnknown': (
    '尚未确认删除结果，请重新读取后核对。',
    '尚未確認刪除結果，請重新讀取後核對。',
    'Deletion is not confirmed. Reload to check the latest logs.',
  ),
  'refreshRequired': (
    '日志或权限已变化，请关闭后重新打开。',
    '日誌或權限已變更，請關閉後重新開啟。',
    'The logs or your permissions changed. Close and reopen this view.',
  ),
  'identityUnavailable': (
    '账号或组织已切换，请关闭后重新打开。',
    '帳號或組織已切換，請關閉後重新開啟。',
    'The account or organization changed. Close and reopen this view.',
  ),
  'notAllowed': (
    '当前无法查看此组织的日志。',
    '目前無法查看此組織的日誌。',
    'You cannot view this organization’s logs now.',
  ),
  'dataInvalid': (
    '日志暂时无法读取，请重新读取。',
    '日誌暫時無法讀取，請重新讀取。',
    'The logs could not be read. Try reloading.',
  ),
  'unavailable': (
    '暂时无法连接日志服务，请稍后重新读取。',
    '暫時無法連線日誌服務，請稍後重新讀取。',
    'The log service is unavailable. Try reloading shortly.',
  ),
  'busy': (
    '正在处理其他组织操作，请稍后重试。',
    '正在處理其他組織操作，請稍後重試。',
    'Another organization action is in progress. Try again shortly.',
  ),
};

String communityLogsText(BuildContext context, String key) {
  final value = communityLogsCopy[key] ?? communityLogsCopy['unavailable']!;
  final locale = AppStrings.of(context).locale;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
