import '../../app/localization/app_strings.dart';

// Only presentation metadata: these IDs are not executable Host commands.
const settingsEntryActions = <String, List<String>>{
  'account-safety': ['accountStatus', 'appeal'],
  'local-data-management': ['exportData', 'clearData'],
  'local-data-storage': ['viewDirectory', 'openDirectory', 'moveDirectory'],
  'entitlement-redemption': ['redeem', 'refreshEntitlements'],
  'application-updates': [
    'checkUpdates',
    'releaseNotes',
    'downloadUpdate',
    'installUpdate',
  ],
  'runtime-status': ['refreshStatus'],
  'local-event-log': ['filterEvents', 'exportEvents', 'clearEvents'],
  'one-click-diagnostics': ['runDiagnostics', 'copyDiagnostics'],
  'local-maintenance': ['openDirectory', 'clearImages', 'repairData'],
  'installation-update-repair': [
    'scanInstallations',
    'repairUpdate',
    'uninstall',
    'cleanRegistrations',
  ],
  'source-rules': ['sourceMode'],
  'player-activity': ['activityAudience', 'activityEvents', 'activityTiming'],
  'continuous-play': ['playEnabled', 'firstReminder', 'repeatReminder'],
};

String settingsEntryText(AppStrings strings, String key) {
  final copy = _copy[key]!;
  if (strings.locale.languageCode == 'en') return copy.$3;
  if (strings.locale.countryCode == 'TW' ||
      strings.locale.scriptCode == 'Hant') {
    return copy.$2;
  }
  return copy.$1;
}

const _copy = <String, (String, String, String)>{
  'description.account-safety': (
    '查看账号限制、处理结果与申诉进度。',
    '查看帳號限制、處理結果與申訴進度。',
    'View account restrictions, decisions, and appeal progress.',
  ),
  'description.local-data-management': (
    '导出本地数据，或选择要清理的内容。',
    '匯出本機資料，或選擇要清理的內容。',
    'Export local data or choose what to clear.',
  ),
  'description.local-data-storage': (
    '查看、打开或更改数据保存位置。',
    '查看、開啟或變更資料儲存位置。',
    'View, open, or change where data is stored.',
  ),
  'description.entitlement-redemption': (
    '使用兑换码获取权益，并查看兑换结果。',
    '使用兌換碼取得權益，並查看兌換結果。',
    'Redeem a code for entitlements and view the result.',
  ),
  'description.application-updates': (
    '检查新版本，查看更新说明，下载并安装更新。',
    '檢查新版本、查看更新說明、下載並安裝更新。',
    'Check for a new version, read release notes, and download and install updates.',
  ),
  'description.runtime-status': (
    '查看应用、游戏、账号、网络与浮层的运行状态。',
    '查看應用程式、遊戲、帳號、網路與浮層的執行狀態。',
    'View app, game, account, network, and overlay status.',
  ),
  'description.local-event-log': (
    '筛选、导出或清空已识别的事件记录。',
    '篩選、匯出或清空已識別的事件記錄。',
    'Filter, export, or clear recognized event records.',
  ),
  'description.one-click-diagnostics': (
    '检查运行环境，复制不含凭据的诊断摘要。',
    '檢查執行環境，複製不含憑證的診斷摘要。',
    'Check the app environment and copy a diagnostic summary without credentials.',
  ),
  'description.local-maintenance': (
    '打开数据目录，清理图片缓存或检查本地数据。',
    '開啟資料目錄、清理圖片快取或檢查本機資料。',
    'Open the data folder, clear image cache, or check local data.',
  ),
  'description.installation-update-repair': (
    '检查重复安装、修复更新，或启动卸载程序。',
    '檢查重複安裝、修復更新，或啟動解除安裝程式。',
    'Check duplicate installations, repair an update, or start the uninstaller.',
  ),
  'description.source-rules': (
    '分别为组织和房间选择正常提醒、仅关键变化或免打扰。',
    '分別為組織與房間選擇正常提醒、僅關鍵變化或免打擾。',
    'Choose normal, important-only, or muted reminders for each organization and room.',
  ),
  'description.player-activity': (
    '选择关注的玩家、需要提醒的动态与显示时机。',
    '選擇關注的玩家、需要提醒的動態與顯示時機。',
    'Choose players to follow, activity to report, and when to show reminders.',
  ),
  'description.continuous-play': (
    '设置首次提醒与后续间隔，提醒自己休息和补水。',
    '設定首次提醒與後續間隔，提醒自己休息與補水。',
    'Set the first reminder and repeat interval for rest and hydration.',
  ),
  'title': ('其他设置', '其他設定', 'Other settings'),
  'intro': (
    '打开条目查看具体选项。标为“暂不可用”的操作尚未启用。',
    '開啟項目查看具體選項。標為「暫不可用」的操作尚未啟用。',
    'Open an entry to see its options. Actions marked “Unavailable” are not enabled yet.',
  ),
  'unavailable': ('暂不可用', '暫不可用', 'Unavailable'),
  'notice': (
    '当前版本尚未启用以下操作。不会更改设置、处理文件或提交请求。',
    '目前版本尚未啟用以下操作。不會變更設定、處理檔案或提交請求。',
    'These actions are not enabled in this version. No settings, files, or requests will be changed or submitted.',
  ),
  'close': ('关闭', '關閉', 'Close'),
  'options': ('操作与选项', '操作與選項', 'Actions and options'),
  'accountStatus': ('查看账号状态', '查看帳號狀態', 'View account status'),
  'appeal': ('查看处理结果与申诉', '查看處理結果與申訴', 'View decisions and appeals'),
  'exportData': ('导出本地数据', '匯出本機資料', 'Export local data'),
  'clearData': ('选择要清理的数据', '選擇要清理的資料', 'Choose data to clear'),
  'viewDirectory': ('查看数据保存位置', '查看資料儲存位置', 'View data location'),
  'openDirectory': ('打开数据文件夹', '開啟資料夾', 'Open data folder'),
  'moveDirectory': ('迁移数据并重启', '移轉資料並重新啟動', 'Move data and restart'),
  'redeem': ('兑换代码', '兌換代碼', 'Redeem code'),
  'refreshEntitlements': ('刷新我的权益', '重新整理我的權益', 'Refresh my entitlements'),
  'checkUpdates': ('检查更新', '檢查更新', 'Check for updates'),
  'releaseNotes': ('查看更新说明', '查看更新說明', 'View release notes'),
  'downloadUpdate': ('下载更新', '下載更新', 'Download update'),
  'installUpdate': ('安装更新并重启', '安裝更新並重新啟動', 'Install update and restart'),
  'refreshStatus': ('刷新运行状态', '重新整理執行狀態', 'Refresh runtime status'),
  'filterEvents': ('按类别筛选事件', '依類別篩選事件', 'Filter events by category'),
  'exportEvents': ('导出事件记录', '匯出事件記錄', 'Export event records'),
  'clearEvents': ('清空事件记录', '清空事件記錄', 'Clear event records'),
  'runDiagnostics': ('运行诊断', '執行診斷', 'Run diagnostics'),
  'copyDiagnostics': ('复制安全摘要', '複製安全摘要', 'Copy safe summary'),
  'clearImages': ('清理图片缓存', '清理圖片快取', 'Clear image cache'),
  'repairData': ('检查与修复本地数据', '檢查與修復本機資料', 'Check and repair local data'),
  'scanInstallations': ('检查重复安装', '檢查重複安裝', 'Check duplicate installations'),
  'repairUpdate': ('修复更新', '修復更新', 'Repair update'),
  'uninstall': ('启动卸载程序', '啟動解除安裝程式', 'Start uninstaller'),
  'cleanRegistrations': (
    '清理失效安装记录',
    '清理失效安裝記錄',
    'Clean stale installation records',
  ),
  'sourceMode': (
    '逐个组织与房间设置提醒方式',
    '逐一設定組織與房間的提醒方式',
    'Set reminders per organization and room',
  ),
  'activityAudience': (
    '选择需要关注的玩家范围',
    '選擇需要關注的玩家範圍',
    'Choose which players to follow',
  ),
  'activityEvents': (
    '选择上线、离线和游戏动态',
    '選擇上線、離線與遊戲動態',
    'Choose online, offline, and game activity',
  ),
  'activityTiming': (
    '设置后台与游戏中的提醒时机',
    '設定背景與遊戲中的提醒時機',
    'Set reminder timing in background and in game',
  ),
  'playEnabled': (
    '启用休息与补水提醒',
    '啟用休息與補水提醒',
    'Enable rest and hydration reminders',
  ),
  'firstReminder': (
    '首次提醒：60 / 90 / 120 / 180 分钟',
    '首次提醒：60 / 90 / 120 / 180 分鐘',
    'First reminder: 60 / 90 / 120 / 180 minutes',
  ),
  'repeatReminder': (
    '后续间隔：60 / 120 分钟',
    '後續間隔：60 / 120 分鐘',
    'Repeat interval: 60 / 120 minutes',
  ),
};
