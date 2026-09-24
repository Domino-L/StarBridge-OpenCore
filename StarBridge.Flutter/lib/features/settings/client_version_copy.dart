import 'package:flutter/widgets.dart';

String clientVersionText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final value = _copy[key]!;
  if (locale.languageCode == 'en') return value.$3;
  if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') {
    return value.$2;
  }
  return value.$1;
}

const _copy = <String, (String, String, String)>{
  'open': ('查看当前版本', '查看目前版本', 'View current version'),
  'title': ('当前客户端版本', '目前客戶端版本', 'Current client version'),
  'loading': ('正在读取…', '正在讀取…', 'Loading…'),
  'unavailable': (
    '暂时无法读取版本，请重试。',
    '暫時無法讀取版本，請重試。',
    'Version unavailable. Try again.',
  ),
  'retry': ('重新读取', '重新讀取', 'Reload'),
  'copy': ('复制版本号', '複製版本號', 'Copy version'),
  'copied': ('版本号已复制', '版本號已複製', 'Version copied'),
  'copyFailed': ('未能复制，请重试。', '無法複製，請重試。', 'Could not copy. Try again.'),
  'close': ('关闭', '關閉', 'Close'),
};
