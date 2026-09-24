import 'package:flutter/widgets.dart';

String installationCheckText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final value = _copy[key]!;
  if (locale.languageCode == 'en') return value.$3;
  if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') {
    return value.$2;
  }
  return value.$1;
}

const _copy = <String, (String, String, String)>{
  'next': (
    '可重新检查；若问题持续，请通过“帮助与支持”联系支持。',
    '可重新檢查；若問題持續，請透過「幫助與支援」聯絡支援。',
    'Check again. If the issue persists, contact support through Help & support.',
  ),
  'title': ('安装与修复', '安裝與修復', 'Installation and repair'),
  'intro': (
    '检查安装状态与可维护性。检查可能短暂创建并立即删除测试文件，以确认数据目录可写；不会读取或清理你的数据。',
    '檢查安裝狀態與可維護性。檢查可能短暫建立並立即刪除測試檔案，以確認資料目錄可寫入；不會讀取或清理你的資料。',
    'Check installation status and maintainability. A temporary test file may be created and immediately removed to check data-folder access. Your data is not read or cleaned.',
  ),
  'scan': ('检查安装', '檢查安裝', 'Check installation'),
  'loading': ('正在检查…', '正在檢查…', 'Checking…'),
  'current': ('当前安装记录', '目前安裝記錄', 'Current installation records'),
  'observed': ('已读取的记录', '已讀取的記錄', 'Records read'),
  'partial': (
    '部分记录未能读取，以下数量可能不完整。',
    '部分記錄未能讀取，以下數量可能不完整。',
    'Some records could not be read. Counts may be incomplete.',
  ),
  'pending': ('以下功能暂不可用', '以下功能暫不可用', 'Not yet available'),
  'repair': ('修复更新', '修復更新', 'Repair update'),
  'uninstall': ('卸载客户端', '解除安裝客戶端', 'Uninstall client'),
  'clean': ('清理安装残留', '清理安裝殘留', 'Clean installation remnants'),
  'close': ('关闭', '關閉', 'Close'),
};
