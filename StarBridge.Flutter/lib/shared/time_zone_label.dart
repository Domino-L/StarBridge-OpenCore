import 'package:flutter/widgets.dart';

/// Presentation only. The stored Windows/IANA identifier never changes with UI
/// language; unfamiliar zones retain their supplied label rather than guessing.
String timeZoneLabel(BuildContext context, String id, {String? fallback}) {
  final locale = Localizations.localeOf(context);
  final translated = _zones[id];
  if (translated == null) return fallback ?? id;
  if (locale.languageCode != 'zh') return translated.$3;
  return locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? translated.$2
      : translated.$1;
}

const _zones = <String, (String, String, String)>{
  'UTC': ('协调世界时', '協調世界時', 'Coordinated Universal Time'),
  'Central America Standard Time': (
    '中美洲标准时间',
    '中美洲標準時間',
    'Central America Standard Time',
  ),
  'Canada Central Standard Time': (
    '加拿大中部标准时间',
    '加拿大中部標準時間',
    'Canada Central Standard Time',
  ),
  'America/Regina': ('加拿大里贾纳', '加拿大里賈納', 'Regina, Canada'),
  'America/Guatemala': ('危地马拉', '瓜地馬拉', 'Guatemala'),
  'China Standard Time': ('中国标准时间', '中國標準時間', 'China Standard Time'),
  'Asia/Shanghai': ('中国上海', '中國上海', 'Shanghai, China'),
  'Taipei Standard Time': ('台北标准时间', '台北標準時間', 'Taipei Standard Time'),
  'Asia/Taipei': ('台北', '台北', 'Taipei'),
  'Asia/Hong_Kong': ('中国香港', '中國香港', 'Hong Kong'),
  'Pacific Standard Time': (
    '北美太平洋时间',
    '北美太平洋時間',
    'North American Pacific Time',
  ),
  'Mountain Standard Time': (
    '北美山区时间',
    '北美山區時間',
    'North American Mountain Time',
  ),
  'US Mountain Standard Time': (
    '美国山区标准时间',
    '美國山區標準時間',
    'US Mountain Standard Time',
  ),
  'Central Standard Time': ('北美中部时间', '北美中部時間', 'North American Central Time'),
  'Eastern Standard Time': ('北美东部时间', '北美東部時間', 'North American Eastern Time'),
  'Atlantic Standard Time': (
    '北美大西洋时间',
    '北美大西洋時間',
    'North American Atlantic Time',
  ),
  'Newfoundland Standard Time': ('纽芬兰时间', '紐芬蘭時間', 'Newfoundland Time'),
  'Alaskan Standard Time': ('阿拉斯加时间', '阿拉斯加時間', 'Alaska Time'),
  'Hawaiian Standard Time': ('夏威夷标准时间', '夏威夷標準時間', 'Hawaii Standard Time'),
  'GMT Standard Time': ('英国时间', '英國時間', 'United Kingdom Time'),
  'W. Europe Standard Time': ('西欧时间', '西歐時間', 'Western European Time'),
  'Central Europe Standard Time': ('中欧时间', '中歐時間', 'Central European Time'),
  'Romance Standard Time': ('巴黎、马德里时间', '巴黎、馬德里時間', 'Paris, Madrid Time'),
  'FLE Standard Time': ('赫尔辛基、基辅时间', '赫爾辛基、基輔時間', 'Helsinki, Kyiv Time'),
  'Tokyo Standard Time': ('日本标准时间', '日本標準時間', 'Japan Standard Time'),
  'Korea Standard Time': ('韩国标准时间', '韓國標準時間', 'Korea Standard Time'),
  'Singapore Standard Time': ('新加坡标准时间', '新加坡標準時間', 'Singapore Standard Time'),
  'India Standard Time': ('印度标准时间', '印度標準時間', 'India Standard Time'),
  'AUS Eastern Standard Time': (
    '澳大利亚东部时间',
    '澳大利亞東部時間',
    'Australian Eastern Time',
  ),
  'E. Australia Standard Time': (
    '澳大利亚东部标准时间',
    '澳大利亞東部標準時間',
    'Australian Eastern Standard Time',
  ),
  'W. Australia Standard Time': (
    '澳大利亚西部标准时间',
    '澳大利亞西部標準時間',
    'Australian Western Standard Time',
  ),
  'New Zealand Standard Time': ('新西兰时间', '紐西蘭時間', 'New Zealand Time'),
};
