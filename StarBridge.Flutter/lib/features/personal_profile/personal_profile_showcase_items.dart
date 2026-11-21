import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../achievements/achievement_collection_port.dart';
import '../gameplay_time/gameplay_time_controller.dart';
import 'personal_profile_achievement_showcase.dart';
import 'personal_profile_models.dart';
import 'personal_profile_module_surface.dart';
import 'personal_profile_showcase_bodies.dart';
import 'personal_profile_showcase_frame.dart';
import 'personal_profile_showcases.dart';

/// Builds a showcase-only item of the single column. Null when there is
/// nothing to show this viewer outside editing (the column skips it).
Widget? buildProfileShowcaseItem(
  BuildContext context, {
  required String id,
  required PersonalProfileProjection projection,
  required bool editing,
  required bool isVisitor,
  required bool includeLocalTime,
  bool visitorView = false,
  GameplayTimeController? gameplayTime,
  List<String>? achievementPicks,
  Widget? controls,
}) {
  final strings = AppStrings.of(context);
  Widget band(String titleKey, Widget child, {StarBridgeIconSemantic? icon}) =>
      PersonalProfileModuleSurface(
        icon: icon ?? StarBridgeIconSemantic.profile,
        titleKey: titleKey,
        headerTrailing: controls,
        child: child,
      );
  switch (id) {
    case PersonalProfileShowcaseIds.tradeCard:
      final facts = projection.publicFacts;
      if (facts == null && !editing) return null;
      return band(
        'profile.showcase.tradeCard',
        facts == null
            ? ProfileCaption(strings.text('profile.tradeCard.ownerHint'))
            : ProfileTradeCardShowcase(facts: facts),
        icon: StarBridgeIconSemantic.marketplace,
      );
    case PersonalProfileShowcaseIds.achievements:
      if (isVisitor) {
        // Only what the server returned for this viewer; never local data.
        final items = projection.showcaseData.publicAchievements;
        if (items == null || items.isEmpty) return null;
        return band(
          'profile.showcase.achievements',
          ProfileAchievementShowcase(items: profileVisitorAchievements(items)),
          icon: StarBridgeIconSemantic.achievement,
        );
      }
      final scope = ProfileAchievementsScope.of(context);
      if (scope == null) {
        return editing
            ? band(
                'profile.showcase.achievements',
                ProfileCaption(
                  strings.text('profile.achievements.unavailable'),
                ),
                icon: StarBridgeIconSemantic.achievement,
              )
            : null;
      }
      return ValueListenableBuilder<AchievementCollection>(
        valueListenable: scope.countedOrCollection,
        builder: (context, counted, _) =>
            ValueListenableBuilder<AchievementCollection>(
              valueListenable: scope.collection,
              builder: (context, collection, _) => PersonalProfileModuleSurface(
                icon: StarBridgeIconSemantic.achievement,
                titleKey: 'profile.showcase.achievements',
                // The owner's count is not part of what visitors see (or preview).
                headerTrailing:
                    controls ??
                    // Shown when the achievements page shows its number too.
                    (counted.isReady &&
                            counted.unknownIds.isEmpty &&
                            !visitorView
                        ? Text(
                            strings
                                .text('profile.achievements.earnedCount')
                                .replaceAll(
                                  '{earned}',
                                  '${counted.catalog.where((d) => counted.isEarned(d.id)).length}',
                                )
                                .replaceAll(
                                  '{total}',
                                  '${counted.catalog.length}',
                                ),
                          )
                        : null),
                child: collection.isReady
                    ? ProfileAchievementShowcase(
                        items: profileOwnerAchievements(
                          collection,
                          achievementPicks,
                        ),
                      )
                    : ProfileCaption(
                        strings.text('profile.achievements.unavailable'),
                      ),
              ),
            ),
      );
  }
  return null;
}

/// Band title of a showcase-only item.
String profileShowcaseTitle(BuildContext context, String id) =>
    AppStrings.of(context).text(switch (id) {
      PersonalProfileShowcaseIds.achievements =>
        'profile.showcase.achievements',
      _ => 'profile.showcase.tradeCard',
    });
