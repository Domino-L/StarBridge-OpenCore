import 'package:flutter/widgets.dart';

String maintenanceText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final entry = _copy[key]!;
  return locale.languageCode == 'en'
      ? entry.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? entry.$2
      : entry.$1;
}

const _copy = <String, (String, String, String)>{
  'title': ('维护工具', '維護工具', 'Maintenance tools'),
  'scope': (
    '只处理当前设备。清理缓存不会重置账号、设置或游玩时长。',
    '只處理目前裝置。清理快取不會重設帳號、設定或遊玩時長。',
    'Changes apply to this device. Cache cleanup does not reset accounts, settings or playtime.',
  ),
  'folder': ('打开数据目录', '開啟資料目錄', 'Open data folder'),
  'clear': ('清理图片缓存', '清理圖片快取', 'Clear image cache'),
  'confirm': (
    '清理可重新下载的组织与舰船图片？头像、用户图片、导入图片和其他数据会保留。图片可能需要重新加载。',
    '清理可重新下載的組織與艦船圖片？頭像、使用者圖片、匯入圖片和其他資料會保留。圖片可能需要重新載入。',
    'Clear downloadable community and ship images? Avatars, user images, imported images and other data are kept. Images may need to reload.',
  ),
  'cancel': ('取消', '取消', 'Cancel'),
  'installedApps': (
    '在 Windows 中管理安装与卸载',
    '在 Windows 中管理安裝與解除安裝',
    'Manage installations in Windows',
  ),
  'installationScope': (
    '卸载由 Windows 中对应版本的官方卸载程序处理。便携副本不自动删除；本页不会调用其他版本的卸载器。',
    '解除安裝由 Windows 中對應版本的官方程式處理。可攜副本不自動刪除；本頁不會呼叫其他版本的解除安裝程式。',
    'Use the matching official uninstaller in Windows. Portable copies are not deleted automatically; this page never invokes another version’s uninstaller.',
  ),
  'opened': ('已打开。', '已開啟。', 'Opened.'),
  'cleared': (
    '已清理可重新下载的图片缓存，其他图片和数据已保留。',
    '已清理可重新下載的圖片快取，其他圖片和資料已保留。',
    'Downloadable image cache cleared. Other images and data were kept.',
  ),
  'failed': (
    '操作未确认完成，请检查后重试。不会自动重复执行。',
    '操作未確認完成，請檢查後重試。不會自動重複執行。',
    'Completion could not be confirmed. Check before trying again. This action is not retried automatically.',
  ),
};
