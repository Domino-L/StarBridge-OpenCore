import 'package:flutter/widgets.dart';

import 'guide_copy_empty.dart';
import 'guide_copy_notice.dart';
import 'guide_copy_tips.dart';
import 'guide_copy_tours.dart';

/// (zh-Hans, zh-Hant, en) copy for the in-app guide; English never falls
/// back to Chinese (see guide_copy_test).
final class GuideCopy {
  const GuideCopy(this.locale);
  factory GuideCopy.of(BuildContext context) =>
      GuideCopy(Localizations.localeOf(context));
  final Locale locale;

  static const tables = [
    _words,
    guideTipWords,
    guideEmptyWords,
    guideTourWords,
    guideNoticeWords,
  ];

  String text(String key) {
    final words =
        _words[key] ??
        guideTipWords[key] ??
        guideEmptyWords[key] ??
        guideTourWords[key] ??
        guideNoticeWords[key]!;
    if (locale.languageCode == 'en') return words.$3;
    if (locale.scriptCode == 'Hant' ||
        const {'TW', 'HK', 'MO'}.contains(locale.countryCode)) {
      return words.$2;
    }
    return words.$1;
  }

  String? maybe(String key) => _has(key) ? text(key) : null;

  static bool _has(String key) =>
      _words.containsKey(key) ||
      guideTipWords.containsKey(key) ||
      guideEmptyWords.containsKey(key) ||
      guideTourWords.containsKey(key) ||
      guideNoticeWords.containsKey(key);

  static const _words = <String, (String, String, String)>{
    'checklist.title': ('新舰长上手', '新艦長上手', 'Getting started'),
    'checklist.collapse': ('收起', '收合', 'Collapse'),
    'checklist.expand': ('展开', '展開', 'Expand'),
    'checklist.dismiss': ('不再显示', '不再顯示', "Don't show again"),
    'checklist.doneTitle': ('上手完成', '上手完成', 'All set'),
    'checklist.doneBody': ('祝航行顺利，o7', '祝航行順利，o7', 'Fly safe, o7'),
    'checklist.close': ('关闭', '關閉', 'Close'),
    'checklist.progress': (
      '{done} / {total}',
      '{done} / {total}',
      '{done} / {total}',
    ),
    'checklist.localFoot': (
      '想跟舰队一起玩、去交易大厅做买卖？换成在线账号，在 设置 › 账号与识别 里切换。',
      '想跟艦隊一起玩、去交易大廳做買賣？換成線上帳號，在 設定 › 帳號與識別 裡切換。',
      'Want to play with your fleet or trade? Switch to an online account in Settings › Account and recognition.',
    ),
    'checklist.recognize.title': ('进游戏试一下', '進遊戲試一下', 'Try it in game'),
    'checklist.recognize.body': (
      '可以进一次游戏服务器，看看能不能正确识别出你在哪、开的什么船。',
      '可以進一次遊戲伺服器，看看能不能正確識別出你在哪、開的什麼船。',
      'Join a game server once and check that StarBridge recognizes where you are and what you fly.',
    ),
    'checklist.hangar.title': ('载入你的机库', '載入你的機庫', 'Load your hangar'),
    'checklist.hangar.body': (
      '从 RSI 官网读取你的飞船、载具。',
      '從 RSI 官網讀取你的飛船、載具。',
      'Read your ships and vehicles from the RSI website.',
    ),
    'checklist.hangar.go': ('去机库', '去機庫', 'Open hangar'),
    'checklist.fleet.title': (
      '前往你的主舰队报到',
      '前往你的主艦隊報到',
      'Check in with your main fleet',
    ),
    'checklist.fleet.body': (
      '查看舰队的当前状况。',
      '查看艦隊的目前狀況。',
      'See what your fleet is up to.',
    ),
    'checklist.fleet.go': ('去主舰队', '去主艦隊', 'Open fleet'),
    'checklist.overlay.title': (
      '调一下游戏内浮层',
      '調一下遊戲內浮層',
      'Set up the in-game overlay',
    ),
    'checklist.overlay.body': (
      '可以实时显示队友状态，调整设置至你的专属浮层。',
      '可以即時顯示隊友狀態，調整設定至你的專屬浮層。',
      'Show your teammates live in game and tune it to your liking.',
    ),
    'checklist.overlay.localBody': (
      '游戏里显示什么、摆在哪，按你的习惯设置。',
      '遊戲裡顯示什麼、擺在哪，按你的習慣設定。',
      'Choose what shows in game and where.',
    ),
    'checklist.overlay.go': ('去浮层', '去浮層', 'Open overlay'),
    'checklist.market.title': ('逛逛交易大厅', '逛逛交易大廳', 'Browse the trading hall'),
    'checklist.market.body': (
      '关注市场动态。',
      '關注市場動態。',
      'Keep an eye on the market.',
    ),
    'checklist.market.go': ('去交易大厅', '去交易大廳', 'Open trading hall'),
    'checklist.friend.title': ('加个好友', '加個好友', 'Add a friend'),
    'checklist.friend.body': (
      '可以在好友进入游戏时获得提醒。',
      '可以在好友進入遊戲時獲得提醒。',
      'Get notified when friends join the game.',
    ),
    'checklist.friend.go': ('加好友', '加好友', 'Add friend'),
    'checklist.tools.title': ('工具', '工具', 'Tools'),
    'checklist.tools.body': (
      '游戏内和游戏外的实用工具。',
      '遊戲內和遊戲外的實用工具。',
      'Handy tools for in and out of the game.',
    ),
    'checklist.tools.go': ('去工具', '去工具', 'Open tools'),
    'checklist.achievements.title': ('成就中心', '成就中心', 'Achievements'),
    'checklist.achievements.body': (
      '包含游戏内和游戏外成就。',
      '包含遊戲內和遊戲外成就。',
      'In-game and out-of-game achievements.',
    ),
    'checklist.achievements.go': ('去成就中心', '去成就中心', 'Open achievements'),
    'settings.title': ('引导', '引導', 'Guides'),
    'settings.body': (
      '关掉的首页清单、页面提示和导览，可以在这里重新打开。',
      '關掉的首頁清單、頁面提示和導覽，可以在這裡重新開啟。',
      'Bring back the home checklist, page tips and tours you closed.',
    ),
    'settings.resetChecklist': (
      '重新显示首页清单',
      '重新顯示首頁清單',
      'Show home checklist again',
    ),
    'settings.resetTips': (
      '重新显示页面提示和导览',
      '重新顯示頁面提示和導覽',
      'Show page tips and tours again',
    ),
    'settings.done': ('已重新打开', '已重新開啟', 'Turned back on'),
  };
}
