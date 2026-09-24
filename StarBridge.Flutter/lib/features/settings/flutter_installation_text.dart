import 'package:flutter/widgets.dart';

String flutterInstallationText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final text = _copy[key]!;
  return locale.languageCode == 'en'
      ? text.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? text.$2
      : text.$1;
}

const _copy = <String, (String, String, String)>{
  'title': ('安装与卸载', '安裝與解除安裝', 'Installation and uninstall'),
  'scope': (
    '管理本机的星海舰桥安装。个人数据和旧版客户端会保留。',
    '管理本機的星海艦橋安裝。個人資料和舊版用戶端會保留。',
    'Manage StarBridge on this device. Personal data and the legacy client are kept.',
  ),
  'scan': ('检查安装状态', '檢查安裝狀態', 'Check installation'),
  'uninstall': ('卸载客户端', '解除安裝用戶端', 'Uninstall client'),
  'clean': ('清理安装残留', '清理安裝殘留', 'Clean installation remnants'),
  'cancel': ('保留', '保留', 'Keep'),
  'portable': (
    '当前版本无需安装即可使用，暂不支持在这里卸载。',
    '目前版本無需安裝即可使用，暫不支援在這裡解除安裝。',
    'This version runs without installation and cannot be uninstalled here.',
  ),
  'noRemnants': (
    '未发现需要清理的安装残留。',
    '未發現需要清理的安裝殘留。',
    'No installation remnants need cleaning.',
  ),
  'installed': (
    '已找到当前客户端的安装位置。',
    '已找到目前用戶端的安裝位置。',
    'The current client’s installation was found.',
  ),
  'other': (
    '已找到另一目录中的客户端，请核对位置后操作。',
    '已找到另一目錄中的用戶端，請核對位置後操作。',
    'A client installation was found in another folder. Check its location before continuing.',
  ),
  'orphaned': (
    '安装目录已不存在，可清理遗留安装记录。',
    '安裝目錄已不存在，可清理遺留安裝記錄。',
    'The installation directory no longer exists. Its stale record can be removed.',
  ),
  'damaged': (
    '安装文件不完整。请使用当前版本的安装包修复后再卸载；不会直接删除目录。',
    '安裝檔案不完整。請使用目前版本的安裝套件修復後再解除安裝；不會直接刪除目錄。',
    'Installation files are incomplete. Repair using this version’s installer before uninstalling; this page will not delete the folder.',
  ),
  'unverified': (
    '无法确认安装归属，已禁止卸载与清理。请检查安装目录。',
    '無法確認安裝歸屬，已禁止解除安裝與清理。請檢查安裝目錄。',
    'Installation ownership could not be verified. Uninstall and cleanup are disabled; check the directory.',
  ),
  'unavailable': (
    '安装维护尚未连接，请重新打开客户端后重试。',
    '安裝維護尚未連線，請重新開啟用戶端後重試。',
    'Installation maintenance is not connected. Restart the client and try again.',
  ),
  'uninstallConfirm': (
    '将打开下列客户端的卸载向导。请按向导关闭客户端并确认卸载。账号、设置、日志和旧版客户端会保留。',
    '將開啟下列用戶端的解除安裝精靈。請依精靈關閉用戶端並確認解除安裝。帳號、設定、記錄和舊版用戶端會保留。',
    'Open the uninstall wizard for the client below. Follow it to close the client and confirm removal. Accounts, settings, logs and the legacy client are kept.',
  ),
  'cleanConfirm': (
    '下列位置的客户端已不存在。仅清理 Windows 中对应的安装记录，不删除文件或个人数据。',
    '下列位置的用戶端已不存在。僅清理 Windows 中對應的安裝記錄，不刪除檔案或個人資料。',
    'The client no longer exists at the location below. Remove only its Windows installation record. No files or personal data will be deleted.',
  ),
  'cleaned': ('失效安装记录已清理。', '失效安裝記錄已清理。', 'Stale installation record removed.'),
  'started': (
    '卸载向导已启动，请在向导中继续。',
    '解除安裝精靈已啟動，請在精靈中繼續。',
    'Uninstall wizard started. Continue in the wizard.',
  ),
  'failed': (
    '操作未确认完成。请重新扫描安装状态；不会自动重复操作。',
    '操作未確認完成。請重新掃描安裝狀態；不會自動重複操作。',
    'Completion could not be confirmed. Scan again to check the installation; this action is not retried automatically.',
  ),
};
