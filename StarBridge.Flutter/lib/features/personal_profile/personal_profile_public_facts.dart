import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_public_header.dart';
import 'personal_profile_trade_strip.dart';

String _copy(BuildContext context, String key) {
  final locale = AppStrings.of(context).locale;
  final i = locale.languageCode == 'en'
      ? 2
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? 1
      : 0;
  return const {
    'nameHint': [
      '下单成功后显示完整 Handle',
      '下單成功後顯示完整 Handle',
      'The full Handle appears once you place an order',
    ],
    'reputation': ['SCM 信誉', 'SCM 信譽', 'SCM reputation'],
    'completedTrades': ['已成交', '已成交', 'Completed trades'],
    'sellOrders': ['出售订单', '出售訂單', 'Sell orders'],
    'buyOrders': ['求购订单', '求購訂單', 'Buy orders'],
    'account': ['账号资料', '帳號資料', 'Account'],
    'lastOnline': ['最后上线', '最後上線', 'Last online'],
    'siteRegistered': ['SCM 注册', 'SCM 註冊', 'Joined SCM'],
    'gameRegistered': ['游戏注册', '遊戲註冊', 'Joined the game'],
    'language': ['语言', '語言', 'Language'],
    'zh': ['中文', '中文', 'Chinese'],
    'en': ['英文', '英文', 'English'],
    'timeZone': ['时区', '時區', 'Time zone'],
    'bans': ['封禁记录', '封禁紀錄', 'Bans'],
    'banned': ['封禁中', '封禁中', 'Banned now'],
    'banTotal': ['累计 {n} 次', '累計 {n} 次', '{n} in total'],
    'noBans': ['无', '無', 'None'],
    'date': ['{y} 年 {m} 月 {d} 日', '{y} 年 {m} 月 {d} 日', '{y}-{mm}-{dd}'],
  }[key]![i];
}

/// Shown under a masked name on a visitor page.
String personalProfileMaskedNameHint(BuildContext context) =>
    _copy(context, 'nameHint');

String _date(BuildContext context, String iso) {
  final parts = iso.split('-');
  return _copy(context, 'date')
      .replaceAll('{y}', parts[0])
      .replaceAll('{mm}', parts[1])
      .replaceAll('{dd}', parts[2])
      .replaceAll('{m}', int.parse(parts[1]).toString())
      .replaceAll('{d}', int.parse(parts[2]).toString());
}

/// What the ban state may say: never the reason or the time. Null when SCM's
/// answer does not prove any of them, since "none" must not be a guess.
ProfileFact? _bans(BuildContext context, PersonalProfilePublicFacts facts) {
  final label = _copy(context, 'bans');
  final count = facts.banCount;
  final total = count != null && count > 0
      ? _copy(context, 'banTotal').replaceAll('{n}', '$count')
      : null;
  if (facts.banned == true) {
    final banned = _copy(context, 'banned');
    return ProfileFact(
      label,
      total == null ? banned : '$banned · $total',
      warning: true,
    );
  }
  if (total != null) return ProfileFact(label, total);
  return facts.banned == false && count == 0
      ? ProfileFact(label, _copy(context, 'noBans'))
      : null;
}

/// The trade and account facts on a page whose owner never chose a visibility.
/// Anything unknown is left out, and a section with nothing to show disappears.
class PersonalProfilePublicFactsBlock extends StatelessWidget {
  const PersonalProfilePublicFactsBlock({
    required this.facts,
    this.window,
    super.key,
  });

  final PersonalProfilePublicFacts facts;
  final ProfileTradeStripData? window;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    ProfileFact? number(String key, int? value) =>
        value == null ? null : ProfileFact(_copy(context, key), '$value');
    ProfileFact? day(String key, String? value) =>
        value == null ? null : ProfileFact(_copy(context, key), _date(context, value));
    final trade = [
      if (facts.reputation case final reputation?)
        ProfileFact(_copy(context, 'reputation'), '★ $reputation'),
      ?number('completedTrades', facts.completedTrades),
      ?number('sellOrders', facts.sellOrders),
      ?number('buyOrders', facts.buyOrders),
    ];
    final account = [
      ?day('lastOnline', facts.lastOnlineDay),
      ?day('siteRegistered', facts.siteRegisteredDay),
      ?day('gameRegistered', facts.gameRegisteredDay),
      if (facts.language case final language?)
        ProfileFact(_copy(context, 'language'), _copy(context, language)),
      if (facts.utcOffsetMinutes case final offset?)
        ProfileFact(
          _copy(context, 'timeZone'),
          PersonalProfilePublicTradeWindow.utcLabel(offset),
        ),
      ?_bans(context, facts),
    ];
    final showTrade = window != null || trade.isNotEmpty;
    return Column(
      key: const Key('profile-public-facts'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTrade) ProfileFactSection(window: window, facts: trade),
        if (showTrade && account.isNotEmpty) SizedBox(height: t.space.lg),
        if (account.isNotEmpty)
          ProfileFactSection(title: _copy(context, 'account'), facts: account),
      ],
    );
  }
}
