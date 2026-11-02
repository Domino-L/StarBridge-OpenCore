import 'package:flutter/widgets.dart';

String clientLicenseText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final copy = _copy[key]!;
  if (locale.languageCode == 'en') return copy.$3;
  if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') return copy.$2;
  return copy.$1;
}

const _copy = <String, (String, String, String)>{
  'open': ('查看使用条款与声明', '查看使用條款與聲明', 'View terms and notices'),
  'title': ('使用条款与声明', '使用條款與聲明', 'Terms and notices'),
  'loading': ('正在读取…', '正在讀取…', 'Loading…'),
  'missing': (
    '未找到许可文件，请检查安装包是否完整。',
    '找不到授權文件，請檢查安裝套件是否完整。',
    'License file not found. Check that the installation is complete.',
  ),
  'unreadable': (
    '无法读取许可文件，请检查安装包是否完整。',
    '無法讀取授權文件，請檢查安裝套件是否完整。',
    'Cannot read the license file. Check that the installation is complete.',
  ),
  'unavailable': (
    '暂时无法读取许可，请稍后重试。',
    '暫時無法讀取授權條款，請稍後重試。',
    'The license is unavailable. Try again shortly.',
  ),
  'retry': ('重试', '重試', 'Retry'),
  'close': ('关闭', '關閉', 'Close'),
};
