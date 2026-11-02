import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';

/// Shared visitor-facing copy. Identity and private sharing preferences are
/// deliberately absent from the public presence vocabulary.
String memberBoardText(BuildContext context, String key) {
  return memberBoardTextForLocale(AppStrings.of(context).locale, key);
}

String memberBoardTextForLocale(Locale locale, String key) {
  if (key == 'appOnline') {
    return AppStrings.resolve(locale).text('presence.online');
  }
  const copy = <String, (String, String, String)>{
    'member': ('成员', '成員', 'Member'),
    'role': ('角色', '角色', 'Role'),
    'rank': ('RSI 官网职位', 'RSI 官網職位', 'RSI rank'),
    'presence': ('状态', '狀態', 'Status'),
    'server': ('服务器', '伺服器', 'Server'),
    'ship': ('飞船', '飛船', 'Ship'),
    'location': ('位置', '位置', 'Location'),
    'actions': ('操作', '操作', 'Actions'),
    'all': ('全部', '全部', 'All'),
    'online': ('在线', '線上', 'Online'),
    'inGame': ('游戏中', '遊戲中', 'In game'),
    'away': ('暂离', '暫離', 'Away'),
    'offline': ('离线', '離線', 'Offline'),
    'unknown': ('—', '—', '—'),
    'hidden': ('暂无可见信息', '暫無可見資訊', 'No visible information'),
    'restricted': ('暂无可见信息', '暫無可見資訊', 'No visible information'),
    'notInGame': ('未进入游戏', '未進入遊戲', 'Not in game'),
    'notInServer': ('未进入服务器', '未進入伺服器', 'Not in a server'),
    'waitingRecognition': ('等待识别', '等待識別', 'Waiting for recognition'),
    'waitingServerSync': ('等待服务器同步', '等待伺服器同步', 'Waiting for server sync'),
    'locationPending': ('地点待确认', '地點待確認', 'Location pending confirmation'),
    'lowConfidenceLocation': ('低可信度位置', '低可信度位置', 'Low-confidence location'),
    'total': ('共 {n} 人', '共 {n} 人', '{n} members'),
    'updated': ('更新于 {time}', '更新於 {time}', 'Updated {time}'),
    'pageOnline': ('本页在线', '本頁線上', 'Online on this page'),
    'pageInGame': ('本页游戏中', '本頁遊戲中', 'In game on this page'),
    'pageScope': (
      '在线与游戏人数仅统计当前页',
      '線上與遊戲人數僅統計目前頁面',
      'Presence counts cover this page only',
    ),
    'search': ('搜索成员', '搜尋成員', 'Search members'),
    'submit': ('提交搜索', '提交搜尋', 'Search'),
    'previous': ('上一页', '上一頁', 'Previous'),
    'first': ('首页', '首頁', 'First page'),
    'next': ('下一页', '下一頁', 'Next'),
    'page': ('第 {n} 页', '第 {n} 頁', 'Page {n}'),
    'pages': ('第 {n} / {total} 页', '第 {n} / {total} 頁', 'Page {n} of {total}'),
    'jump': ('跳转', '跳轉', 'Go'),
    'pageSize': ('每页', '每頁', 'Per page'),
    'pageNumber': ('页码', '頁碼', 'Page number'),
    'loading': ('正在加载成员…', '正在載入成員…', 'Loading members…'),
    'refreshing': ('正在更新成员…', '正在更新成員…', 'Updating members…'),
    'refreshFailed': (
      '更新未完成，请重试。',
      '更新未完成，請重試。',
      'Update incomplete. Try again.',
    ),
    'empty': ('没有匹配的成员', '沒有符合的成員', 'No matching members'),
    'retry': ('重试', '重試', 'Retry'),
    'self': ('你', '你', 'You'),
  };
  final value = copy[key];
  if (value == null) throw StateError('Missing organization member copy: $key');
  return locale.languageCode == 'en'
      ? value.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}
