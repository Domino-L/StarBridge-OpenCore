import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/presence_color.dart';
import '../../app/shell/chrome/presence_label.dart';
import '../../app/shell/chrome/shell_chrome_projection.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_models.dart';
import 'personal_profile_public_facts.dart';
import 'personal_profile_public_header.dart';
import 'personal_profile_showcase_bodies.dart';
import 'personal_profile_showcase_copy.dart';
import 'personal_profile_showcase_frame.dart';
import 'personal_profile_trade_strip.dart';

/// Right rail of the Steam-style page: status, trading hours (always public),
/// organizations (always, user 11-08) and stats.
class PersonalProfileSideRail extends StatelessWidget {
  const PersonalProfileSideRail({
    required this.projection,
    required this.isSelf,
    this.presence,
    this.trade,
    this.publicOnly = false,
    this.gameplayHours,
    this.ownerFacts,
    this.tradeIncludesFacts = false,
    super.key,
  });

  final PersonalProfileProjection projection;
  final bool isSelf;
  final ValueListenable<ShellChromeProjection>? presence;

  /// The trading-hours block from the composition layer; null hides it.
  final Widget? trade;
  final bool publicOnly;
  final int? gameplayHours;
  final PersonalProfilePublicFacts? ownerFacts;

  /// The owner/preview composition already appends facts to its async strip.
  final bool tradeIncludesFacts;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String copy(String key) => profileShowcaseCopy(context, key);
    final numbers = MaterialLocalizations.of(context);
    final trade = this.trade;
    final hasTradeReputation =
        trade is ProfileTradeStrip &&
        trade.data?.reputation?.isNotEmpty == true;
    final facts = publicOnly ? null : projection.publicFacts;
    final hangar = projection.hangarSummary;
    final labels = personalProfilePublicFactLabels(context);
    final stats = <(String, String)>[
      if (facts?.sellOrders case final value?)
        (labels.sellOrders, numbers.formatDecimal(value)),
      if (facts?.buyOrders case final value?)
        (labels.buyOrders, numbers.formatDecimal(value)),
      if (!publicOnly && projection.favoriteShips.isNotEmpty)
        (copy('favoriteCount'), '${projection.favoriteShips.length}'),
      if (!publicOnly && hangar.isAvailable && hangar.manufacturerCount > 0)
        (
          copy('manufacturers'),
          numbers.formatDecimal(hangar.manufacturerCount),
        ),
    ];
    final lastOnline = facts?.lastOnlineDay;
    final accountFacts = publicOnly
        ? null
        : ownerFacts ?? projection.accountFacts;
    final showAccount =
        accountFacts != null && personalProfileHasAccountFacts(accountFacts);
    // Trade first, then the account facts, in one band: the owner and every
    // visitor see the same order and look (user 11-08).
    final Widget? tradeSection = accountFacts == null
        ? trade
        : !personalProfileHasTradeFacts(accountFacts)
        ? trade
        : ProfileOwnerTradeFactsScope(
            facts: accountFacts,
            child: isSelf || tradeIncludesFacts
                ? trade ??
                      Builder(
                        builder: (context) =>
                            ProfileOwnerTradeFactsScope.supplement(context),
                      )
                : Column(
                    children: [
                      ?trade,
                      Builder(
                        builder: (context) =>
                            ProfileOwnerTradeFactsScope.supplement(
                              context,
                              hasReputation: hasTradeReputation,
                            ),
                      ),
                    ],
                  ),
          );
    final sections = <Widget>[
      // User 11-11: playtime lives at the top of the rail, the same for the
      // owner and every visitor who may see the whole page.
      if (!publicOnly)
        ProfileGameplayShowcase(
          projection: projection,
          accountHours: gameplayHours,
        ),
      if (presence != null)
        ProfileShowcaseBand(
          key: const Key('profile-rail-status'),
          title: copy('onlineTitle'),
          child: ValueListenableBuilder<ShellChromeProjection>(
            valueListenable: presence!,
            builder: (context, current, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.of(context).text(current.presenceKey),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: presenceColor(tokens.colors, current.presenceKey),
                  ),
                ),
                ProfileCaption(
                  gamePresenceLabel(AppStrings.of(context), current),
                ),
              ],
            ),
          ),
        )
      else if (lastOnline != null)
        ProfileShowcaseBand(
          key: const Key('profile-rail-status'),
          title: copy('onlineTitle'),
          child: ProfileCaption(
            copy('lastOnline').replaceAll(
              '{date}',
              personalProfileFactDate(context, lastOnline),
            ),
          ),
        ),
      if (trade != null ||
          accountFacts != null &&
              (personalProfileHasTradeFacts(accountFacts) || showAccount))
        ProfileShowcaseBand(
          key: const Key('profile-rail-trade'),
          title: copy('tradeHours'),
          trailing: Text(copy('alwaysPublic')),
          child: personalProfileTradeThenAccount(
            context,
            trade: tradeSection,
            account: showAccount
                ? PersonalProfilePublicFactsBlock(
                    key: Key(
                      isSelf
                          ? 'profile-owner-account-facts'
                          : 'profile-visitor-account-facts',
                    ),
                    facts: accountFacts,
                    showTrade: false,
                  )
                : null,
          ),
        ),
      ProfileShowcaseBand(
        key: const Key('profile-rail-organizations'),
        title: copy('orgTitle'),
        child: ProfileOrganizationList(projection: projection, isSelf: isSelf),
      ),
      if (stats.isNotEmpty)
        ProfileShowcaseBand(
          key: const Key('profile-rail-stats'),
          title: copy('statsTitle'),
          child: Column(
            children: [
              for (final (label, value) in stats)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.colors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: tokens.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ];
    return Column(
      key: const Key('profile-side-rail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) SizedBox(height: tokens.space.md),
          sections[index],
        ],
      ],
    );
  }
}
