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

bool personalProfileHasAccountFacts(PersonalProfilePublicFacts facts) =>
    facts.lastOnlineDay != null ||
    facts.siteRegisteredDay != null ||
    facts.gameRegisteredDay != null ||
    facts.language != null ||
    facts.utcOffsetMinutes != null ||
    facts.banned == true ||
    (facts.banCount ?? 0) > 0 ||
    facts.banned == false && facts.banCount == 0;

bool personalProfileHasTradeFacts(PersonalProfilePublicFacts facts) =>
    facts.reputation != null ||
    facts.completedTrades != null ||
    facts.sellOrders != null ||
    facts.buyOrders != null;

/// The trade and account facts on a page whose owner never chose a visibility.
/// Anything unknown is left out, and a section with nothing to show disappears.
class PersonalProfilePublicFactsBlock extends StatelessWidget {
  const PersonalProfilePublicFactsBlock({
    required this.facts,
    this.window,
    this.showAccount = true,
    this.showTrade = true,
    this.skipReputation = false,
    this.skipCompletedTrades = false,
    super.key,
  });

  final PersonalProfilePublicFacts facts;
  final ProfileTradeStripData? window;
  final bool showAccount;
  final bool showTrade;
  final bool skipReputation;
  final bool skipCompletedTrades;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    ProfileFact? number(String key, int? value) =>
        value == null ? null : ProfileFact(_copy(context, key), '$value');
    ProfileFact? day(String key, String? value) => value == null
        ? null
        : ProfileFact(_copy(context, key), _date(context, value));
    final trade = [
      if (!skipReputation && facts.reputation != null)
        ProfileFact(_copy(context, 'reputation'), '★ ${facts.reputation}'),
      if (!skipCompletedTrades)
        ?number('completedTrades', facts.completedTrades),
      ?number('sellOrders', facts.sellOrders),
      ?number('buyOrders', facts.buyOrders),
    ];
    final account = showAccount
        ? [
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
          ]
        : <ProfileFact>[];
    final hasTrade = showTrade && (window != null || trade.isNotEmpty);
    return Column(
      key: const Key('profile-public-facts'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasTrade) ProfileFactSection(window: window, facts: trade),
        if (hasTrade && account.isNotEmpty) SizedBox(height: t.space.lg),
        if (account.isNotEmpty)
          ProfileFactSection(title: _copy(context, 'account'), facts: account),
      ],
    );
  }
}

/// The trade band's body on every profile page, the owner's included: the
/// trade days, window and numbers first, then the account facts (user 11-08:
/// the owner's page must look exactly like what visitors see).
Widget personalProfileTradeThenAccount(
  BuildContext context, {
  Widget? trade,
  Widget? account,
}) {
  if (trade == null || account == null) {
    return trade ?? account ?? const SizedBox.shrink();
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [trade, SizedBox(height: context.tokens.space.lg), account],
  );
}

/// Joins optional owner numbers to the existing asynchronously loaded trade
/// strip. The composition layer reports which summary it already rendered.
class ProfileOwnerTradeFactsScope extends InheritedWidget {
  const ProfileOwnerTradeFactsScope({
    required this.facts,
    required super.child,
    super.key,
  });
  final PersonalProfilePublicFacts facts;

  /// The facts this scope supplies, or null outside one.
  static PersonalProfilePublicFacts? factsOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ProfileOwnerTradeFactsScope>()
      ?.facts;

  static Widget supplement(
    BuildContext context, {
    bool hasReputation = false,
    bool hasCompletedTrades = false,
  }) {
    final facts = context
        .dependOnInheritedWidgetOfExactType<ProfileOwnerTradeFactsScope>()
        ?.facts;
    return facts == null
        ? const SizedBox.shrink()
        : PersonalProfilePublicFactsBlock(
            facts: facts,
            showAccount: false,
            skipReputation: hasReputation,
            skipCompletedTrades: hasCompletedTrades,
          );
  }

  @override
  bool updateShouldNotify(ProfileOwnerTradeFactsScope oldWidget) =>
      facts != oldWidget.facts;
}

/// Labels of the trade card numbers, shared with the Steam-style showcase.
({
  String reputation,
  String completedTrades,
  String sellOrders,
  String buyOrders,
})
personalProfilePublicFactLabels(BuildContext context) => (
  reputation: _copy(context, 'reputation'),
  completedTrades: _copy(context, 'completedTrades'),
  sellOrders: _copy(context, 'sellOrders'),
  buyOrders: _copy(context, 'buyOrders'),
);

/// The trade card's date line: SCM and game registration and the ban state.
/// Unknown values are left out, as in [PersonalProfilePublicFactsBlock].
List<(String, String)> personalProfilePublicFactDates(
  BuildContext context,
  PersonalProfilePublicFacts facts,
) => [
  if (facts.siteRegisteredDay case final day?)
    (_copy(context, 'siteRegistered'), _date(context, day)),
  if (facts.gameRegisteredDay case final day?)
    (_copy(context, 'gameRegistered'), _date(context, day)),
  if (_bans(context, facts) case final bans?) (bans.label, bans.value),
];

/// "2026 年 11 月 2 日" for an ISO day, as on the public facts.
String personalProfileFactDate(BuildContext context, String iso) =>
    _date(context, iso);
