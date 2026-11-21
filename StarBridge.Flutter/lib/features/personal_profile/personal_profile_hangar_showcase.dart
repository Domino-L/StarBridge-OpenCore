import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_hangar_overview.dart';
import 'personal_profile_models.dart';
import 'personal_profile_ship_names.dart';
import 'personal_profile_showcase_copy.dart';
import 'personal_profile_showcase_frame.dart';

/// 舰船概览 in the single column (accepted preview ProfileSteam): one large
/// number, one bar per role, and the most recently added ship.
class ProfileHangarShowcase extends StatelessWidget {
  const ProfileHangarShowcase({required this.summary, super.key});
  final PersonalProfileHangarSummary summary;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final numbers = MaterialLocalizations.of(context);
    final populated = summary.categories.where((s) => s.count > 0).toList();
    final largest = populated.fold<int>(1, (m, s) => s.count > m ? s.count : m);
    final count = Column(
      key: const Key('profile-hangar-count-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          numbers.formatDecimal(summary.shipCount),
          style: TextStyle(
            fontSize: 46,
            height: 1,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: tokens.colors.textPrimary,
          ),
        ),
        ProfileCaption(profileShowcaseCopy(context, 'ships')),
        if (summary.manufacturerCount > 0) ...[
          SizedBox(height: tokens.space.sm),
          Text(
            '${numbers.formatDecimal(summary.manufacturerCount)} '
            '${profileShowcaseCopy(context, 'manufacturers')}',
            style: TextStyle(fontSize: 13, color: tokens.colors.textSecondary),
          ),
        ],
        if (summary.estimatedValueLabel.isNotEmpty)
          Wrap(
            key: const Key('profile-hangar-value-panel'),
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Same wording as the grid panel: estimate, or the known part.
              ProfileCaption(
                strings.text(
                  summary.unpricedCount == null
                      ? 'profile.hangar.estimatedValue'
                      : summary.unpricedCount! > 0
                      ? 'profile.local.knownValue'
                      : 'profile.local.estimatedValue',
                ),
              ),
              Text(
                summary.estimatedValueLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.colors.textPrimary,
                ),
              ),
            ],
          ),
        if ((summary.unpricedCount ?? 0) > 0)
          ProfileCaption(
            '${summary.unpricedCount} ${strings.text('profile.local.unpriced')}',
          ),
      ],
    );
    final bars = Column(
      key: const Key('profile-hangar-composition-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileCaption(strings.text('profile.hangar.composition')),
        const SizedBox(height: 4),
        for (var index = 0; index < populated.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    strings.text(populated[index].labelKey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: tokens.colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: populated[index].count / largest,
                      child: SizedBox(
                        height: 7,
                        child: ColoredBox(
                          key: Key('profile-hangar-composition-segment-$index'),
                          color: profileShipSliceColor(
                            context,
                            populated[index],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${populated[index].count}',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: tokens.colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final recentShip = summary.recentlyAddedShip;
    final recent = recentShip == null
        ? null
        : Column(
            key: const Key('profile-hangar-recent-ship-panel'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileCaption(
                summary.recentlyAddedAtLabel.isEmpty
                    ? strings.text('profile.hangar.recentlyAdded')
                    : '${strings.text('profile.hangar.recentlyAdded')} · '
                          '${summary.recentlyAddedAtLabel}',
              ),
              const SizedBox(height: 5),
              if (summary.recentlyAddedShipImageAsset.isNotEmpty)
                AspectRatio(
                  // Ship picture cards are 2:1 (hangar line, 11-02).
                  aspectRatio: 2,
                  child: Image.asset(
                    summary.recentlyAddedShipImageAsset,
                    key: const Key('profile-hangar-recent-ship-image'),
                    cacheWidth: 400,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        ColoredBox(color: tokens.domainColors.ship.soft),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                PersonalProfileShipNames.primary(context, recentShip),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.colors.textPrimary,
                ),
              ),
            ],
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (narrow) ...[
              count,
              if (populated.isNotEmpty) ...[
                SizedBox(height: tokens.space.md),
                bars,
              ],
              if (recent != null) ...[
                SizedBox(height: tokens.space.md),
                SizedBox(width: 220, child: recent),
              ],
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 124, child: count),
                  SizedBox(width: tokens.space.lg),
                  Expanded(child: populated.isEmpty ? const SizedBox() : bars),
                  if (recent != null) ...[
                    SizedBox(width: tokens.space.lg),
                    SizedBox(width: 170, child: recent),
                  ],
                ],
              ),
            if (summary.syncedAtLabel.isNotEmpty) ...[
              SizedBox(height: tokens.space.sm),
              ProfileCaption(
                key: const Key('profile-hangar-sync-footer'),
                _syncLine(context),
              ),
            ],
          ],
        );
      },
    );
  }

  String _syncLine(BuildContext context) {
    final strings = AppStrings.of(context);
    final sourceKey = summary.sourceLabelKey.isEmpty
        ? 'profile.hangar.source.rsiSync'
        : summary.sourceLabelKey;
    return [
      strings.text(sourceKey),
      if (!sourceKey.startsWith('profile.local.'))
        '${strings.text('profile.hangar.syncedAt')} ${summary.syncedAtLabel}'
      else
        summary.syncedAtLabel,
    ].join(' · ');
  }
}
