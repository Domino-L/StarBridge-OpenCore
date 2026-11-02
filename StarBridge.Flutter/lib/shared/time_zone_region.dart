import 'package:flutter/widgets.dart';

/// The region people recognise behind a time zone offset (user 2026-10-29:
/// "时区后也该跟用户能看懂的位置"): "美国中部", "北京时间". Looked up by the
/// stored Windows or IANA identifier first; a bare offset falls back to the
/// most common region for it, and anything else shows no region at all
/// rather than a guess.
String? timeZoneRegionLabel(
  BuildContext context,
  String? id,
  int? standardOffsetMinutes,
) {
  final entry =
      (id == null ? null : _byId[id]) ??
      (standardOffsetMinutes == null ? null : _byOffset[standardOffsetMinutes]);
  if (entry == null) return null;
  final locale = Localizations.localeOf(context);
  if (locale.languageCode != 'zh') return entry.$3;
  return locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? entry.$2
      : entry.$1;
}

typedef _Region = (String, String, String);

const _Region _beijing = ('北京时间', '北京時間', 'Beijing');
const _Region _taipei = ('台北', '台北', 'Taipei');
const _Region _hongKong = ('香港', '香港', 'Hong Kong');
const _Region _singapore = ('新加坡', '新加坡', 'Singapore');
const _Region _tokyo = ('日本', '日本', 'Japan');
const _Region _seoul = ('韩国', '韓國', 'Korea');
const _Region _india = ('印度', '印度', 'India');
const _Region _bangkok = ('泰国、越南', '泰國、越南', 'Thailand, Vietnam');
const _Region _sydney = ('澳大利亚东部', '澳大利亞東部', 'Eastern Australia');
const _Region _perth = ('澳大利亚西部', '澳大利亞西部', 'Western Australia');
const _Region _auckland = ('新西兰', '紐西蘭', 'New Zealand');
const _Region _london = ('英国', '英國', 'United Kingdom');
const _Region _berlin = ('中欧', '中歐', 'Central Europe');
const _Region _paris = ('法国、西班牙', '法國、西班牙', 'France, Spain');
const _Region _helsinki = ('东欧', '東歐', 'Eastern Europe');
const _Region _moscow = ('莫斯科', '莫斯科', 'Moscow');
const _Region _dubai = ('阿联酋', '阿聯酋', 'UAE');
const _Region _usEast = ('美国东部', '美國東部', 'US Eastern');
const _Region _usCentral = ('美国中部', '美國中部', 'US Central');
const _Region _usMountain = ('美国山区', '美國山區', 'US Mountain');
const _Region _usPacific = ('美国西部', '美國西部', 'US Pacific');
const _Region _alaska = ('阿拉斯加', '阿拉斯加', 'Alaska');
const _Region _hawaii = ('夏威夷', '夏威夷', 'Hawaii');
const _Region _atlantic = ('加拿大大西洋', '加拿大大西洋', 'Atlantic Canada');
const _Region _brazil = ('巴西', '巴西', 'Brazil');
const _Region _argentina = ('阿根廷', '阿根廷', 'Argentina');
const _Region _mexico = ('墨西哥', '墨西哥', 'Mexico');
const _Region _utc = ('协调世界时', '協調世界時', 'UTC');

const _byId = <String, _Region>{
  'UTC': _utc,
  'Etc/UTC': _utc,
  'Asia/Shanghai': _beijing,
  'Asia/Chongqing': _beijing,
  'China Standard Time': _beijing,
  'Asia/Taipei': _taipei,
  'Taipei Standard Time': _taipei,
  'Asia/Hong_Kong': _hongKong,
  'Asia/Macau': _hongKong,
  'Asia/Singapore': _singapore,
  'Singapore Standard Time': _singapore,
  'Asia/Kuala_Lumpur': _singapore,
  'Asia/Manila': _singapore,
  'Asia/Tokyo': _tokyo,
  'Tokyo Standard Time': _tokyo,
  'Asia/Seoul': _seoul,
  'Korea Standard Time': _seoul,
  'Asia/Kolkata': _india,
  'Asia/Calcutta': _india,
  'India Standard Time': _india,
  'Asia/Bangkok': _bangkok,
  'Asia/Ho_Chi_Minh': _bangkok,
  'Asia/Jakarta': _bangkok,
  'SE Asia Standard Time': _bangkok,
  'Australia/Sydney': _sydney,
  'Australia/Melbourne': _sydney,
  'Australia/Brisbane': _sydney,
  'AUS Eastern Standard Time': _sydney,
  'E. Australia Standard Time': _sydney,
  'Australia/Perth': _perth,
  'W. Australia Standard Time': _perth,
  'Pacific/Auckland': _auckland,
  'New Zealand Standard Time': _auckland,
  'Europe/London': _london,
  'GMT Standard Time': _london,
  'Europe/Berlin': _berlin,
  'Europe/Amsterdam': _berlin,
  'Europe/Rome': _berlin,
  'Europe/Vienna': _berlin,
  'Europe/Warsaw': _berlin,
  'Europe/Stockholm': _berlin,
  'W. Europe Standard Time': _berlin,
  'Central Europe Standard Time': _berlin,
  'Central European Standard Time': _berlin,
  'Europe/Paris': _paris,
  'Europe/Madrid': _paris,
  'Europe/Brussels': _paris,
  'Romance Standard Time': _paris,
  'Europe/Helsinki': _helsinki,
  'Europe/Kyiv': _helsinki,
  'Europe/Kiev': _helsinki,
  'Europe/Athens': _helsinki,
  'FLE Standard Time': _helsinki,
  'GTB Standard Time': _helsinki,
  'Europe/Moscow': _moscow,
  'Russian Standard Time': _moscow,
  'Asia/Dubai': _dubai,
  'Arabian Standard Time': _dubai,
  'America/New_York': _usEast,
  'America/Toronto': _usEast,
  'America/Detroit': _usEast,
  'Eastern Standard Time': _usEast,
  'America/Chicago': _usCentral,
  'America/Winnipeg': _usCentral,
  'Central Standard Time': _usCentral,
  'America/Denver': _usMountain,
  'America/Phoenix': _usMountain,
  'America/Edmonton': _usMountain,
  'Mountain Standard Time': _usMountain,
  'US Mountain Standard Time': _usMountain,
  'America/Los_Angeles': _usPacific,
  'America/Vancouver': _usPacific,
  'Pacific Standard Time': _usPacific,
  'America/Anchorage': _alaska,
  'Alaskan Standard Time': _alaska,
  'Pacific/Honolulu': _hawaii,
  'Hawaiian Standard Time': _hawaii,
  'America/Halifax': _atlantic,
  'Atlantic Standard Time': _atlantic,
  'America/Sao_Paulo': _brazil,
  'E. South America Standard Time': _brazil,
  'America/Argentina/Buenos_Aires': _argentina,
  'Argentina Standard Time': _argentina,
  'America/Mexico_City': _mexico,
  'Central Standard Time (Mexico)': _mexico,
};

/// Standard offsets with one clear best-known region. Offsets shared by
/// unrelated regions (UTC+2, UTC+3, UTC+10, …) are deliberately absent.
const _byOffset = <int, _Region>{
  0: _london,
  60: _berlin,
  330: _india,
  420: _bangkok,
  480: _beijing,
  540: _tokyo,
  720: _auckland,
  -180: _brazil,
  -300: _usEast,
  -360: _usCentral,
  -420: _usMountain,
  -480: _usPacific,
  -540: _alaska,
  -600: _hawaii,
};
