import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/presence_color.dart';
import '../../app/shell/chrome/presence_label.dart';
import '../../app/shell/chrome/shell_chrome_projection.dart';
import '../../design_system/styles/profile_showcase_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../achievements/achievement_collection_port.dart';
import '../common/user_avatar_menu.dart';
import '../common/user_profile_page.dart';
import 'personal_profile_achievement_showcase.dart';
import 'personal_profile_avatar.dart';
import 'personal_profile_layout.dart';
import 'personal_profile_models.dart';
import 'personal_profile_public_facts.dart';
import 'personal_profile_public_header.dart';
import 'personal_profile_showcase_bodies.dart';
import 'personal_profile_main_role.dart';
import 'personal_profile_showcase_copy.dart';
import 'personal_profile_showcase_frame.dart';

/// Header of the Steam-style page (accepted preview ProfileSteam): avatar in
/// one standard frame (never a rank or entitlement mark), name, status and
/// introduction; on the right the actions, three numbers and the main role.
class PersonalProfileSteamHeader extends StatelessWidget {
  const PersonalProfileSteamHeader({
    required this.projection,
    required this.isSelf,
    this.presence,
    this.actions,
    this.publicOnly = false,
    this.gameplayHours,
    this.accountFacts,
    this.showAchievementCount = false,
    this.showMainRoleHint = false,
    super.key,
  });

  final PersonalProfileProjection projection;
  final bool isSelf;
  final ValueListenable<ShellChromeProjection>? presence;
  final Widget? actions;

  /// A visitor outside the visibility: avatar and name only.
  final bool publicOnly;

  /// The owner's total hours, when known, for the numbers.
  final int? gameplayHours;

  /// SCM account facts of a page the viewer may see in full: the service
  /// time comes from its game registration day.
  final PersonalProfilePublicFacts? accountFacts;

  /// The owner's own view: earned achievements lead the numbers.
  final bool showAchievementCount;

  /// The owner's own view of a page that can save a main role: with none
  /// set, says so where the main role would be (never to visitors).
  final bool showMainRoleHint;

  /// The same numbers for the owner and every visitor who may see the whole
  /// page (user 11-11): ships, service time and achievements. Each one only
  /// when known; nothing on a page the viewer may not see. Visitors get HK's
  /// count (swap 5); the owner's own page counts exactly like the
  /// achievements page, SCM's own achievements included (user 11-13), and
  /// shows HK's number only until that page's count is known.
  List<(String, String)> _numbers(BuildContext context, int? ownCount) {
    if (publicOnly) return const [];
    final numbers = MaterialLocalizations.of(context);
    final hangar = projection.hangarSummary;
    String copy(String key) => profileShowcaseCopy(context, key);
    final service = personalProfileServiceTime(
      context,
      accountFacts?.gameRegisteredDay,
    );
    return [
      if (hangar.isAvailable)
        (numbers.formatDecimal(hangar.shipCount), copy('ships')),
      if (service != null) (service, copy('serviceTime')),
      if (ownCount ?? projection.showcaseData.achievementCount
          case final count?)
        (
          numbers.formatDecimal(count),
          AppStrings.of(context).text('profile.achievements.count'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scope = showAchievementCount && !publicOnly
        ? ProfileAchievementsScope.of(context)
        : null;
    if (scope == null) return _build(context, null);
    return ValueListenableBuilder<AchievementCollection>(
      valueListenable: scope.countedOrCollection,
      builder: (context, collection, _) => _build(
        context,
        // Shown exactly when the achievements page shows its number.
        collection.isReady && collection.unknownIds.isEmpty
            ? collection.catalog.where((d) => collection.isEarned(d.id)).length
            : null,
      ),
    );
  }

  Widget _build(BuildContext context, int? ownCount) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    // The owner always sees it; visitors and the preview only where the
    // skilled roles showcase is shown (a hidden one hides it here too).
    final mainRole =
        publicOnly ||
            !showAchievementCount &&
                !PersonalProfileLayout.normalize(projection.moduleLayout).any(
                  (item) =>
                      item.isVisible &&
                      item.moduleId == PersonalProfileModuleIds.skilledRoles,
                )
        ? null
        : profileMainRole(projection);
    final numbers = _numbers(context, ownCount);
    final avatar = Container(
      width: 124,
      height: 124,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surfaces.ground.fill,
        border: Border.all(
          color: tokens.colors.textPrimary.withValues(alpha: 0.28),
        ),
      ),
      child: UserAvatarMenu(
        name: projection.callSign,
        avatarImageData: projection.avatarImageData,
        isSelf: isSelf,
        target: isSelf ? null : UserProfileTargetScope.of(context),
        child: PersonalProfileAvatar(
          callSign: projection.callSign,
          styleIndex: projection.avatarStyle,
          imageData: projection.avatarImageData,
          size: 118,
        ),
      ),
    );
    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          projection.callSign.isEmpty
              ? strings.text('profile.local.noCallSign')
              : projection.callSign,
          key: const Key('profile-steam-name'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: tokens.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (presence != null)
              ValueListenableBuilder<ShellChromeProjection>(
                valueListenable: presence!,
                builder: (context, current, _) => Wrap(
                  spacing: 12,
                  children: [
                    _Status(
                      label: strings.text(current.presenceKey),
                      color: presenceColor(tokens.colors, current.presenceKey),
                    ),
                    _Status(
                      label: gamePresenceLabel(strings, current),
                      color: presenceColor(
                        tokens.colors,
                        current.gamePresenceKey,
                      ),
                    ),
                  ],
                ),
              ),
            if (publicOnly && projection.nameMasked)
              ProfileCaption(personalProfileMaskedNameHint(context))
            else if (!publicOnly && projection.gameHandle.isNotEmpty)
              ProfileCaption('@${projection.gameHandle}'),
          ],
        ),
        if (!publicOnly && projection.about.isNotEmpty) ...[
          SizedBox(height: tokens.space.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              projection.about,
              key: const Key('profile-steam-about'),
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: tokens.colors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (actions != null)
          Align(alignment: AlignmentDirectional.centerEnd, child: actions),
        if (numbers.isNotEmpty) ...[
          SizedBox(height: tokens.space.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < numbers.length; index++) ...[
                  if (index > 0) ...[
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: profileHairline(context),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ProfileBigNumber(
                      value: numbers[index].$1,
                      label: numbers[index].$2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (mainRole == null && showMainRoleHint && !publicOnly) ...[
          SizedBox(height: tokens.space.sm),
          Container(
            padding: const EdgeInsets.only(top: 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: profileHairline(context))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profileShowcaseCopy(context, 'mainRole'),
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.colors.textSecondary,
                  ),
                ),
                SizedBox(width: tokens.space.sm),
                const Expanded(child: ProfileMainRoleHint()),
              ],
            ),
          ),
        ],
        if (mainRole != null) ...[
          SizedBox(height: tokens.space.sm),
          Container(
            padding: const EdgeInsets.only(top: 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: profileHairline(context))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    profileShowcaseCopy(context, 'mainRole'),
                    style: TextStyle(
                      fontSize: 13,
                      color: tokens.colors.textSecondary,
                    ),
                  ),
                ),
                // Long role names (English, large text) wrap within half the row.
                Flexible(
                  child: Text(
                    mainRole.displayLabel ?? strings.text(mainRole.labelKey),
                    key: const Key('profile-steam-main-role'),
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ProfileShowcasePalette.mainRole(
                        Theme.of(context).brightness,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      key: const Key('profile-identity-header'),
      builder: (context, constraints) {
        final identity = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            SizedBox(width: tokens.space.lg),
            Expanded(child: who),
          ],
        );
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              SizedBox(height: tokens.space.md),
              side,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: identity),
            SizedBox(width: tokens.space.lg),
            SizedBox(width: PersonalProfileSteamColumn.railWidth, child: side),
          ],
        );
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    ],
  );
}

/// Time since the game registration day (user 11-11): from the first full
/// year on, years with one decimal cut down, never rounded up ("3.4 年" until
/// 3.5 years are complete); before that, whole days ("326 天"). Null without
/// a valid day or for a day in the future.
String? personalProfileServiceTime(
  BuildContext context,
  String? isoDay, {
  DateTime? now,
}) {
  final years = personalProfileServiceTenths(isoDay, now: now);
  if (years == null) return null;
  final numbers = MaterialLocalizations.of(context);
  if (years.tenths == null) {
    return profileShowcaseCopy(
      context,
      'serviceDays',
    ).replaceAll('{n}', numbers.formatDecimal(years.days));
  }
  final tenths = years.tenths!;
  return profileShowcaseCopy(
    context,
    'serviceYears',
  ).replaceAll('{n}', '${numbers.formatDecimal(tenths ~/ 10)}.${tenths % 10}');
}

/// [days] since registration, and from a full year on the completed tenths of
/// a year: whole calendar years plus the elapsed share of the current one.
({int days, int? tenths})? personalProfileServiceTenths(
  String? isoDay, {
  DateTime? now,
}) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(isoDay ?? '');
  if (match == null) return null;
  final start = DateTime.utc(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
  if (start.month != int.parse(match[2]!)) return null;
  final today = (now ?? DateTime.now());
  final end = DateTime.utc(today.year, today.month, today.day);
  if (end.isBefore(start)) return null;
  final days = end.difference(start).inDays;
  DateTime anniversary(int years) =>
      DateTime.utc(start.year + years, start.month, start.day);
  var years = end.year - start.year;
  if (anniversary(years).isAfter(end)) years--;
  if (years < 1) return (days: days, tenths: null);
  final from = anniversary(years);
  final share =
      end.difference(from).inDays /
      anniversary(years + 1).difference(from).inDays;
  return (days: days, tenths: years * 10 + (share * 10).floor().clamp(0, 9));
}
