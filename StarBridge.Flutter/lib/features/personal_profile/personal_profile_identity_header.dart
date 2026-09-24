import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/shell_chrome_projection.dart';
import '../../app/shell/chrome/presence_color.dart';
import '../../app/shell/chrome/presence_label.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_avatar.dart';
import '../common/user_avatar_menu.dart';
import '../common/user_profile_page.dart';
import 'personal_profile_affiliation_mark.dart';
import 'personal_profile_models.dart';

class PersonalProfileIdentityHeader extends StatelessWidget {
  const PersonalProfileIdentityHeader({
    required this.projection,
    this.presence,
    this.isSelf = true,
    super.key,
  });

  final PersonalProfileProjection projection;
  final bool isSelf;
  final ValueListenable<ShellChromeProjection>? presence;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: const Key('profile-identity-header'),
      role: SurfaceRole.raised,
      fillOpacity: 0.90,
      padding: EdgeInsets.all(tokens.space.xl),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 820) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Identity(projection: projection, presence: presence, isSelf: isSelf),
                _SectionDivider(horizontal: true),
                _Introduction(projection: projection),
                _SectionDivider(horizontal: true),
                _Affiliations(projection: projection),
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _Identity(projection: projection, presence: presence, isSelf: isSelf),
                ),
                _SectionDivider(horizontal: false),
                Expanded(flex: 4, child: _Introduction(projection: projection)),
                _SectionDivider(horizontal: false),
                Expanded(flex: 3, child: _Affiliations(projection: projection)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.projection, this.presence, required this.isSelf});

  final bool isSelf;

  final PersonalProfileProjection projection;
  final ValueListenable<ShellChromeProjection>? presence;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        UserAvatarMenu(
          name: projection.callSign,
          avatarImageData: projection.avatarImageData,
          isSelf: isSelf,
          target: isSelf ? null : UserProfileTargetScope.of(context),
          child: PersonalProfileAvatar(
            callSign: projection.callSign,
            styleIndex: projection.avatarStyle,
            imageData: projection.avatarImageData,
            size: tokens.density.controlHeight * 2.25,
          ),
        ),
        SizedBox(width: tokens.space.lg),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                projection.callSign.isEmpty
                    ? strings.text('profile.local.noCallSign')
                    : projection.callSign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.space.xxs),
              Text(
                projection.gameHandle.isEmpty
                    ? '—'
                    : '@${projection.gameHandle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
              SizedBox(height: tokens.space.sm),
              Wrap(
                spacing: tokens.space.sm,
                runSpacing: tokens.space.xs,
                children: [
                  if (presence != null)
                    ValueListenableBuilder<ShellChromeProjection>(
                      valueListenable: presence!,
                      builder: (context, current, _) => Wrap(
                        spacing: tokens.space.sm,
                        runSpacing: tokens.space.xs,
                        children: [
                          _PresenceLabel(
                            label: strings.text(current.presenceKey),
                            color: presenceColor(
                              tokens.colors,
                              current.presenceKey,
                            ),
                          ),
                          _PresenceLabel(
                            label: gamePresenceLabel(strings, current),
                            color: presenceColor(
                              tokens.colors,
                              current.gamePresenceKey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (projection.presenceIntent ==
                      PersonalProfilePresenceIntent.availableSupport)
                    _QuietLabel(
                      label: strings.text('profile.presence.availableSupport'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Introduction extends StatelessWidget {
  const _Introduction({required this.projection});

  final PersonalProfileProjection projection;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.space.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('profile.about.title'),
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.sm),
          Text(
            projection.about.isEmpty
                ? strings.text('profile.about.empty')
                : projection.about,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
            ),
          ),
        ],
      ),
    );
  }
}

class _PresenceLabel extends StatelessWidget {
  const _PresenceLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: tokens.icons.statusDot,
          height: tokens.icons.statusDot,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: tokens.space.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _Affiliations extends StatelessWidget {
  const _Affiliations({required this.projection});

  final PersonalProfileProjection projection;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.space.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('profile.affiliation.title'),
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.sm),
          if (projection.affiliations.isEmpty)
            Text(
              strings.text(
                projection.local?.remoteAvailable == false
                    ? 'profile.local.unknown'
                    : 'profile.affiliation.empty',
              ),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            )
          else
            for (
              var index = 0;
              index < projection.affiliations.length;
              index++
            ) ...[
              _AffiliationRow(affiliation: projection.affiliations[index]),
              if (index != projection.affiliations.length - 1)
                SizedBox(height: tokens.space.sm),
            ],
        ],
      ),
    );
  }
}

class _AffiliationRow extends StatelessWidget {
  const _AffiliationRow({required this.affiliation});

  final PersonalProfileAffiliationSummary affiliation;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PersonalProfileAffiliationMark(affiliation: affiliation),
        SizedBox(width: tokens.space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                affiliation.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: tokens.space.xxs),
              Text(
                '${strings.text(affiliation.positionLabelKey)} · '
                '${affiliation.code}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuietLabel extends StatelessWidget {
  const _QuietLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: tokens.colors.textSecondary),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return horizontal
        ? Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.space.lg),
            child: Divider(
              height: tokens.stroke.hairline,
              color: tokens.surfaces.raised.border,
            ),
          )
        : VerticalDivider(
            width: 1,
            thickness: tokens.stroke.hairline,
            color: tokens.surfaces.raised.border,
          );
  }
}
