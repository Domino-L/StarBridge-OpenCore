import 'package:flutter/widgets.dart';

String trayQuickPanelText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final values = _copy[key]!;
  if (locale.languageCode == 'en') return values.$3;
  if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') {
    return values.$2;
  }
  return values.$1;
}

const _copy = <String, (String, String, String)>{
  'brand': ('星海舰桥', '星海艦橋', 'StarBridge'),
  'presence': ('在线状态', '上線狀態', 'Presence'),
  'presence.away': ('暂离', '暫離', 'Away'),
  'presence.inGame': ('游戏中', '遊戲中', 'In game'),
  'presence.unknown': ('连接待确认', '連線待確認', 'Connection unconfirmed'),
  'runtime.running': ('正在运行', '正在執行', 'Running'),
  'runtime.background': ('后台运行中', '背景執行中', 'Running in background'),
  'runtime.unavailable': ('状态暂不可用', '狀態暫不可用', 'Status unavailable'),
  'overlay': ('游戏浮层', '遊戲浮層', 'Game overlay'),
  'overlay.enabled': ('已开启', '已開啟', 'Enabled'),
  'overlay.disabled': ('未开启', '未開啟', 'Disabled'),
  'overlay.unavailable': ('暂不可用', '暫不可用', 'Unavailable'),
  'scene': ('当前场景', '目前場景', 'Current scene'),
  'unknown': ('暂不可用', '暫不可用', 'Unavailable'),
  'enable': ('开启浮层', '開啟浮層', 'Enable overlay'),
  'disable': ('关闭浮层', '關閉浮層', 'Disable overlay'),
  'open': ('打开星海舰桥', '開啟星海艦橋', 'Open StarBridge'),
  'settings': ('浮层设置', '浮層設定', 'Overlay settings'),
  'exit': ('完全退出', '完全結束', 'Quit StarBridge'),
  'close': ('关闭快捷面板', '關閉快捷面板', 'Close quick panel'),
  'busy': ('正在处理…', '正在處理…', 'Working…'),
  'failed': (
    '未能完成操作，请重试。',
    '無法完成操作，請重試。',
    'Could not complete the action. Try again.',
  ),
};
