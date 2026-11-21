import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

/// Words of the Steam-style profile (accepted preview ProfileSteam,
/// 2026-11-02): simplified Chinese, traditional Chinese, English.
String profileShowcaseCopy(BuildContext context, String key) {
  final locale = AppStrings.of(context).locale;
  final i = locale.languageCode == 'en'
      ? 2
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? 1
      : 0;
  return const {
    'mainRole': ['主岗位', '主崗位', 'Main role'],
    'setMainRole': ['设为主岗位', '設為主崗位', 'Set as main role'],
    'mainRoleMark': ['（主岗位）', '（主崗位）', ' (main role)'],
    'noneChosen': ['还没有选', '還沒有選', 'None chosen yet'],
    'mainRoleCancel': ['主岗位 · 取消', '主崗位 · 取消', 'Main role · Remove'],
    'mainRoleHint': ['设一个主岗位', '設一個主崗位', 'Set a main role'],
    'mainRoleWhere': [
      '在“编辑个人页 › 擅长岗位”里设',
      '在「編輯個人頁 › 擅長崗位」裡設',
      'In Edit profile › Skilled roles',
    ],
    'mainRolePickTitle': ['主岗位', '主崗位', 'Main role'],
    'mainRolePickNote': [
      '从已勾选的岗位里选一个，最多一个；不设也可以。',
      '從已勾選的崗位裡選一個，最多一個；不設也可以。',
      'Pick one of the roles you ticked, at most one. Optional.',
    ],
    'mainRolePickEmpty': [
      '先勾选擅长岗位，再选一个设为主岗位。',
      '先勾選擅長崗位，再選一個設為主崗位。',
      'Tick your roles first, then set one as the main role.',
    ],
    'rhythm': ['活动节奏', '活動節奏', 'Activity'],
    'skilled': ['擅长岗位', '擅長崗位', 'Good at'],
    'wantsToJoin': ['想参与', '想參與', 'Wants to join'],
    'gameplayTitle': ['游戏时长', '遊戲時長', 'Playtime'],
    'weekdays': ['工作日', '工作日', 'Weekdays'],
    'weekends': ['周末', '週末', 'Weekends'],
    'hour0': ['0 点', '0 點', '0:00'],
    'hour24': ['24 点', '24 點', '24:00'],
    'noWindow': ['还没有填写常玩时段', '還沒有填寫常玩時段', 'No usual hours set yet'],
    'tradeTitle': ['交易名片', '交易名片', 'Trading card'],
    'fromScm': ['来自 SCM', '來自 SCM', 'From SCM'],
    'orgTitle': ['组织', '組織', 'Organizations'],
    'orgShowcase': ['组织展柜', '組織展櫃', 'Organizations'],
    'onlineTitle': ['在线状态', '在線狀態', 'Status'],
    'tradeHours': ['交易时段', '交易時段', 'Trading hours'],
    'alwaysPublic': ['始终公开', '始終公開', 'Always public'],
    'statsTitle': ['统计', '統計', 'Stats'],
    'ships': ['艘舰船', '艘艦船', 'ships'],
    'shipsStat': ['舰船', '艦船', 'Ships'],
    'manufacturers': ['制造商', '製造商', 'Manufacturers'],
    'favoriteCount': ['收藏舰船', '收藏艦船', 'Favourite ships'],
    'playtimeStat': ['游戏时长', '遊戲時長', 'Playtime'],
    'serviceTime': ['服役时间', '服役時間', 'In service'],
    'serviceYears': ['{n} 年', '{n} 年', '{n} yr'],
    'serviceDays': ['{n} 天', '{n} 天', '{n} d'],
    'hoursUnit': ['{n} 小时', '{n} 小時', '{n} h'],
    'lastOnline': ['最后上线 {date}', '最後上線 {date}', 'Last online {date}'],
    'editShowcases': ['编辑展柜', '編輯展櫃', 'Edit showcases'],
    'moveUp': ['上移', '上移', 'Move up'],
    'moveDown': ['下移', '下移', 'Move down'],
    'hide': ['移除展柜', '移除展櫃', 'Remove showcase'],
    'addShowcase': ['再加一个展柜', '再加一個展櫃', 'Add a showcase'],
  }[key]![i];
}
