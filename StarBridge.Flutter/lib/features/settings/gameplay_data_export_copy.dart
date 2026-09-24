import 'package:flutter/widgets.dart';

String gameplayExportCopy(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final value = _copy[key]!;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}

const _copy = <String, (String, String, String)>{
  'title': ('导出游玩数据', '匯出遊玩資料', 'Export gameplay data'),
  'description': (
    '将当前账号的游玩时长和记录设置保存为新的 JSON 文件。',
    '將目前帳號的遊玩時長與記錄設定儲存為新的 JSON 檔案。',
    'Save this account’s playtime and recording settings to a new JSON file.',
  ),
  'working': ('正在导出…', '正在匯出…', 'Exporting…'),
  'saved': ('游玩数据已导出。', '遊玩資料已匯出。', 'Gameplay data exported.'),
  'cancelled': ('已取消导出。', '已取消匯出。', 'Export cancelled.'),
  'unavailable': (
    '暂时无法导出，请稍后重试。',
    '暫時無法匯出，請稍後重試。',
    'Export is unavailable. Try again later.',
  ),
  'accountChanged': (
    '账号已变更，请重新打开此页面。',
    '帳號已變更，請重新開啟此頁面。',
    'The account changed. Reopen this page.',
  ),
  'dataUnavailable': (
    '无法读取游玩数据，请先在游玩数据设置中重新读取。',
    '無法讀取遊玩資料，請先在遊玩資料設定中重新讀取。',
    'Could not read gameplay data. Refresh it in gameplay settings first.',
  ),
  'fileExists': (
    '文件已存在，请换一个文件名。',
    '檔案已存在，請換一個檔名。',
    'The file already exists. Choose a different name.',
  ),
  'invalidDestination': (
    '请选择应用数据目录以外的普通文件夹，并保存为 JSON 文件。',
    '請選擇應用程式資料目錄以外的一般資料夾，並儲存為 JSON 檔案。',
    'Choose a regular folder outside the app data folder and save as JSON.',
  ),
  'busy': (
    '已有导出正在进行，请先完成或取消。',
    '已有匯出正在進行，請先完成或取消。',
    'An export is in progress. Finish or cancel it first.',
  ),
  'failed': (
    '未能保存，请检查文件夹权限与剩余空间后重试。',
    '未能儲存，請檢查資料夾權限與剩餘空間後重試。',
    'Could not save. Check folder permissions and free space, then try again.',
  ),
  'unknown': (
    '未能确认导出结果，请检查所选文件夹。',
    '未能確認匯出結果，請檢查所選資料夾。',
    'Could not confirm the export result. Check the selected folder.',
  ),
};
