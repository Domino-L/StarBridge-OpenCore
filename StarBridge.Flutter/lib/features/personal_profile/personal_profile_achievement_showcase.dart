import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../achievements/achievement_art.dart';
import '../achievements/achievement_catalog.dart';
import '../achievements/achievement_collection_port.dart';
import 'personal_profile_public_facts.dart';
import 'personal_profile_showcase_frame.dart';
import 'personal_profile_showcases.dart';

/// The owner's achievement collection, supplied by the composition layer so
/// the profile shares the achievements page's read instead of starting its own.
class ProfileAchievementsScope extends InheritedWidget {
  const ProfileAchievementsScope({
    required this.collection,
    required this.activate,
    required super.child,
    this.counted,
    super.key,
  });

  /// What the showcase lists and the picker offers (this app's catalog).
  final ValueListenable<AchievementCollection> collection;

  /// What the owner's numbers count: the same as the achievements page
  /// (with the SCM ones). Falls back to [collection].
  final ValueListenable<AchievementCollection>? counted;
  ValueListenable<AchievementCollection> get countedOrCollection =>
      counted ?? collection;
  final Future<void> Function() activate;

  static ProfileAchievementsScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfileAchievementsScope>();

  @override
  bool updateShouldNotify(ProfileAchievementsScope oldWidget) =>
      collection != oldWidget.collection || counted != oldWidget.counted;
}

typedef ProfileShownAchievement = ({
  AchievementDefinition definition,
  DateTime? earnedAt,
  int rank,
});

/// Ranked achievements are stored as `<id>-<rank>`; the art and name belong
/// to the base definition.
AchievementDefinition? profileAchievementDefinition(
  String id, [
  List<AchievementDefinition> catalog = achievementCatalog,
]) {
  for (final definition in catalog) {
    if (definition.id == id) return definition;
  }
  final ranked = RegExp(r'^(.*)-[1-5]$').firstMatch(id);
  return ranked == null
      ? null
      : profileAchievementDefinition(ranked.group(1)!, catalog);
}

/// What the owner's showcase shows: the picks still earned, in pick order;
/// with no picks, the most recent earned (same rule the server applies).
List<ProfileShownAchievement> profileOwnerAchievements(
  AchievementCollection collection,
  List<String>? picks,
) {
  if (!collection.isReady) return const [];
  final earned = [
    for (final definition in collection.catalog)
      if (collection.isEarned(definition.id))
        (
          definition: definition,
          earnedAt: collection.dateFor(definition.id),
          rank: collection.rank(definition.id),
        ),
  ];
  if (picks != null && picks.isNotEmpty) {
    return [
      for (final id in picks)
        ...earned.where((item) => item.definition.id == id),
    ].take(PersonalProfileShowcases.maximumAchievements).toList();
  }
  earned.sort(
    (a, b) => (b.earnedAt ?? DateTime(0)).compareTo(a.earnedAt ?? DateTime(0)),
  );
  return earned.take(PersonalProfileShowcases.maximumAchievements).toList();
}

List<ProfileShownAchievement> profileVisitorAchievements(
  List<PersonalProfilePublicAchievement> items,
) => [
  for (final item in items)
    if (profileAchievementDefinition(item.id) case final definition?)
      (
        definition: definition,
        earnedAt: item.earnedAt,
        rank: definition.isSeries
            ? int.tryParse(
                    RegExp(r'-([1-5])$').firstMatch(item.id)?.group(1) ?? '',
                  ) ??
                  1
            : 0,
      ),
];

String profileAchievementName(
  BuildContext context,
  AchievementDefinition definition,
) => definition.serverName ?? AppStrings.of(context).text(definition.nameKey);

/// One large achievement and up to eight small ones (accepted preview).
class ProfileAchievementShowcase extends StatelessWidget {
  const ProfileAchievementShowcase({required this.items, super.key});
  final List<ProfileShownAchievement> items;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    if (items.isEmpty) {
      return ProfileCaption(strings.text('profile.achievements.none'));
    }
    final hero = items.first;
    final rest = items.skip(1).toList();
    String date(DateTime? at) {
      if (at == null) return '';
      final local = at.toLocal();
      final iso =
          '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      return strings
          .text('profile.achievements.earnedOn')
          .replaceAll('{date}', personalProfileFactDate(context, iso));
    }

    final heroBlock = Column(
      key: const Key('profile-achievement-hero'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AchievementArt(
          definition: hero.definition,
          earned: true,
          rank: hero.rank,
          size: 196,
        ),
        SizedBox(height: tokens.space.xs),
        Text(
          profileAchievementName(context, hero.definition),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: tokens.colors.textPrimary,
          ),
        ),
        if (hero.earnedAt != null) ProfileCaption(date(hero.earnedAt)),
      ],
    );
    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final size = ((constraints.maxWidth - 8 * 3) / 4).clamp(48.0, 120.0);
        return Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final item in rest)
              SizedBox(
                width: size,
                child: Column(
                  key: Key('profile-achievement-${item.definition.id}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AchievementArt(
                      definition: item.definition,
                      earned: true,
                      rank: item.rank,
                      size: size,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profileAchievementName(context, item.definition),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: tokens.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 480
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heroBlock,
                if (rest.isNotEmpty) ...[
                  SizedBox(height: tokens.space.md),
                  grid,
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 196, child: heroBlock),
                SizedBox(width: tokens.space.md),
                Expanded(child: grid),
              ],
            ),
    );
  }
}

/// Lets the owner choose up to nine earned achievements, in order.
Future<List<String>?> showProfileAchievementPicker(
  BuildContext context, {
  required AchievementCollection collection,
  required List<String> selected,
}) => showStarBridgeDialog<List<String>>(
  context,
  builder: (_) => _AchievementPicker(collection: collection, initial: selected),
);

class _AchievementPicker extends StatefulWidget {
  const _AchievementPicker({required this.collection, required this.initial});
  final AchievementCollection collection;
  final List<String> initial;

  @override
  State<_AchievementPicker> createState() => _AchievementPickerState();
}

class _AchievementPickerState extends State<_AchievementPicker> {
  late final _picked = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final earned = profileOwnerAchievements(widget.collection, null);
    final limit = PersonalProfileShowcases.maximumAchievements;
    return AlertDialog(
      key: const Key('profile-achievement-picker'),
      title: Text(strings.text('profile.achievements.pick')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileCaption(strings.text('profile.achievements.pickHint')),
            SizedBox(height: tokens.space.sm),
            if (earned.isEmpty)
              ProfileCaption(strings.text('profile.achievements.none'))
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in earned)
                      StarBridgeCheckboxTile(
                        controlKey: Key(
                          'profile-achievement-pick-${item.definition.id}',
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        dense: true,
                        value: _picked.contains(item.definition.id),
                        label: profileAchievementName(context, item.definition),
                        subtitle: _picked.contains(item.definition.id)
                            ? '#${_picked.indexOf(item.definition.id) + 1}'
                            : null,
                        onChanged:
                            _picked.contains(item.definition.id) ||
                                _picked.length < limit
                            ? (on) => setState(() {
                                if (on == true) {
                                  _picked.add(item.definition.id);
                                } else {
                                  _picked.remove(item.definition.id);
                                }
                              })
                            : null,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('profile-achievement-picker-cancel'),
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source),
          child: Text(strings.text('common.cancel')),
        ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.primary,
          controlKey: const Key('profile-achievement-picker-apply'),
          onActivate: (source) => dismissStarBridgeDialog<List<String>>(
            context,
            source: source,
            result: List<String>.unmodifiable(_picked),
          ),
          child: Text(strings.text('profile.favorites.apply')),
        ),
      ],
    );
  }
}
