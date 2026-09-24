import 'package:flutter/widgets.dart';

String dataLocationCopy(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final value = _copy[key]!;
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}

const _copy = <String, (String, String, String)>{
  'title': ('数据保存位置', '資料儲存位置', 'Data location'),
  'path': ('当前文件夹', '目前資料夾', 'Current folder'),
  'copy': ('复制路径', '複製路徑', 'Copy path'),
  'copied': ('路径已复制', '路徑已複製', 'Path copied'),
  'copyFailed': ('未能复制，请重试。', '未能複製，請重試。', 'Could not copy. Try again.'),
  'open': ('打开文件夹', '開啟資料夾', 'Open folder'),
  'opened': ('已打开文件夹', '已開啟資料夾', 'Folder opened'),
  'openFailed': (
    '无法打开文件夹，请检查是否仍存在及访问权限。',
    '無法開啟資料夾，請檢查是否仍存在及存取權限。',
    'Could not open the folder. Check that it exists and you have access.',
  ),
  'failed': (
    '暂时无法读取保存位置，正在自动重试。',
    '暫時無法讀取儲存位置，正在自動重試。',
    'Could not read the data location. Retrying automatically.',
  ),
  'missing': (
    '文件夹不存在或无法访问。',
    '資料夾不存在或無法存取。',
    'The folder is missing or inaccessible.',
  ),
  'retry': ('重新读取', '重新讀取', 'Refresh'),
  'move': ('更改保存位置', '變更儲存位置', 'Change location'),
  'confirmTitle': ('迁移本机数据？', '遷移本機資料？', 'Move local data?'),
  'confirmBody': (
    '客户端将退出，迁移完成后自动重新打开。原文件夹会保留，不会移动游戏或账号。',
    '用戶端將結束，遷移完成後自動重新開啟。原資料夾會保留，不會移動遊戲或帳號。',
    'The client will close and reopen after migration. The original folder is kept; your game and account are not moved.',
  ),
  'from': ('当前文件夹', '目前資料夾', 'Current folder'),
  'to': ('新文件夹', '新資料夾', 'New folder'),
  'keep': ('暂不迁移', '暫不遷移', 'Not now'),
  'migrate': ('迁移并重启', '遷移並重新啟動', 'Move and restart'),
  'migrationChooseFailed': (
    '无法使用所选文件夹。请选择可用的空文件夹。',
    '無法使用所選資料夾。請選擇可用的空資料夾。',
    'That folder cannot be used. Choose an accessible empty folder.',
  ),
  'migrationStartFailed': (
    '迁移未能启动，客户端保持打开。请重新选择后再试。',
    '遷移未能啟動，用戶端保持開啟。請重新選擇後再試。',
    'Migration could not start. The client remains open. Choose the folder again and retry.',
  ),
  'migrationWpfRunning': (
    '请先从托盘完全退出旧版星海舰桥，再重新选择迁移目录。数据尚未移动。',
    '請先從系統匣完全結束舊版星海艦橋，再重新選擇遷移目錄。資料尚未移動。',
    'Fully quit the WPF client from its tray menu, then choose the destination again. No data has moved.',
  ),
  'migrationCompleted': (
    '本机数据已迁移。原文件夹仍保留。',
    '本機資料已遷移。原資料夾仍保留。',
    'Local data moved. The original folder is still available.',
  ),
  'migrationFailed': (
    '本机数据未迁移，仍使用原文件夹。请在设置中重新选择。',
    '本機資料未遷移，仍使用原資料夾。請在設定中重新選擇。',
    'Local data was not moved. The original folder is still in use. Choose a location again in Settings.',
  ),
  'close': ('关闭', '關閉', 'Close'),
};
