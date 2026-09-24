import 'package:flutter/widgets.dart';

String runtimeStatusText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final text = _copy[key] ?? _copy['unknown']!;
  if (locale.languageCode == 'en') return text.$3;
  if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') return text.$2;
  return text.$1;
}

const _copy = <String, (String, String, String)>{
  'title': ('运行概况', '執行概況', 'Runtime overview'),
  'details': ('技术详情', '技術詳情', 'Technical details'),
  'hideDetails': ('收起技术详情', '收起技術詳情', 'Hide technical details'),
  'loading': ('正在读取…', '正在讀取…', 'Loading…'),
  'unknown': ('暂不可用', '暫不可用', 'Unavailable'),
  'partial': (
    '部分信息暂时无法读取。',
    '部分資訊暫時無法讀取。',
    'Some information could not be loaded.',
  ),
  'refresh': ('刷新', '重新整理', 'Refresh'),
  'close': ('关闭', '關閉', 'Close'),
  'overlay': ('浮层状态', '浮層狀態', 'Overlay'),
  'hotkey': ('全局快捷键', '全域快捷鍵', 'Global shortcut'),
  'mode': ('显示模式', '顯示模式', 'Display preset'),
  'startup': ('启动与后台', '啟動與背景', 'Startup and background'),
  'data': ('数据保存目录', '資料儲存目錄', 'Data folder'),
  'images': ('图片缓存目录', '圖片快取目錄', 'Image cache folder'),
  'version': ('当前安装构建版本', '目前安裝組建版本', 'Installed build version'),
  'server': ('服务器地址', '伺服器位址', 'Server address'),
  'cacheMissing': ('未找到或无法访问', '找不到或無法存取', 'Not found or inaccessible'),
  'open': ('正在显示', '正在顯示', 'Visible'),
  'closed': ('未显示', '未顯示', 'Hidden'),
  'failed': ('运行异常', '執行異常', 'Error'),
  'registered': ('已注册，可全局使用', '已註冊，可全域使用', 'Registered for global use'),
  'disabled': ('未启用', '未啟用', 'Disabled'),
  'invalid': ('快捷键无效', '快捷鍵無效', 'Invalid shortcut'),
  'conflict': ('被其他应用占用', '被其他應用程式占用', 'Used by another app'),
  'gameCompatibleOnly': (
    '全局快捷键未能启用，游戏内仍可使用',
    '全域快捷鍵未能啟用，遊戲內仍可使用',
    'The global shortcut could not be enabled; it still works in game',
  ),
  'desktopOnly': (
    '全局快捷键已启用，游戏内兼容功能暂不可用',
    '全域快捷鍵已啟用，遊戲內相容功能暫不可用',
    'Global shortcut enabled; in-game compatibility is unavailable',
  ),
  'autoStart': ('开机启动', '開機啟動', 'Start with Windows'),
  'trayStart': ('启动至托盘', '啟動至系統匣', 'Start in tray'),
  'on': ('开启', '開啟', 'On'),
  'off': ('关闭', '關閉', 'Off'),
  'background': (
    '关闭窗口后继续运行',
    '關閉視窗後繼續執行',
    'Keep running after closing the window',
  ),
  'exit': ('关闭窗口后退出', '關閉視窗後結束', 'Exit after closing the window'),
};
