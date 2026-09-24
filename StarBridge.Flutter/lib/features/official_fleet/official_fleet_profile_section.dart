import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_models.dart';
import 'official_fleet_profile_identity_source.dart';

class OfficialFleetProfileSection extends StatelessWidget {
  const OfficialFleetProfileSection({
    required this.fleet,
    required this.observedAtUtc,
    super.key,
  });

  final OfficialFleetSummary fleet;
  final DateTime? observedAtUtc;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final profile = fleet.profile;
    return Column(
      key: const Key('official-fleet-profile'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileIdentitySurface(fleet: fleet),
        SizedBox(height: tokens.space.md),
        if (profile == null)
          const _ProfileDetailsUnavailable()
        else ...[
          _NarrativeSurface(profile: profile),
          if (profile.hasFocus ||
              profile.hasAttributes ||
              profile.tags.isNotEmpty) ...[
            SizedBox(height: tokens.space.md),
            _ProfileFacts(profile: profile),
          ],
          SizedBox(height: tokens.space.md),
          OfficialFleetProfileIdentitySource(
            fleet: fleet,
            observedAtUtc: observedAtUtc,
          ),
        ],
      ],
    );
  }
}

class _ProfileIdentitySurface extends StatelessWidget {
  const _ProfileIdentitySurface({required this.fleet});

  final OfficialFleetSummary fleet;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final profile = fleet.profile;
    return StarBridgeSurface(
      role: SurfaceRole.raised,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: tokens.shape.medium,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (profile?.bannerUrl case final bannerUrl?)
              SizedBox(
                key: const Key('official-fleet-profile-banner'),
                height: 156,
                child: Image.network(
                  bannerUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(tokens.space.lg),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final identity = Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _ProfileLogo(fleet: fleet),
                      SizedBox(width: tokens.space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fleet.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            SizedBox(height: tokens.space.xxs),
                            Text(
                              fleet.sid,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: tokens.colors.textSecondary,
                                    letterSpacing: 1.2,
                                  ),
                            ),
                            SizedBox(height: tokens.space.sm),
                            _OfficialRankLine(fleet: fleet),
                          ],
                        ),
                      ),
                    ],
                  );
                  final facts = Wrap(
                    spacing: tokens.space.sm,
                    runSpacing: tokens.space.sm,
                    children: [
                      if (profile?.recruitingLabel case final label?)
                        _IdentityFact(
                          icon: StarBridgeIconSemantic.friends,
                          label: label,
                          color: tokens.colors.success,
                        ),
                      if (profile?.memberCount case final count?)
                        _IdentityFact(
                          icon: StarBridgeIconSemantic.officialFleet,
                          label: AppStrings.of(context)
                              .text('officialFleet.profile.memberCount')
                              .replaceAll('{count}', count.toString()),
                          color: tokens.domainColors.recon.foreground,
                        ),
                    ],
                  );
                  if (constraints.maxWidth < 700 || facts.children.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        identity,
                        if (facts.children.isNotEmpty) ...[
                          SizedBox(height: tokens.space.md),
                          facts,
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: identity),
                      SizedBox(width: tokens.space.lg),
                      facts,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileLogo extends StatelessWidget {
  const _ProfileLogo({required this.fleet});

  final OfficialFleetSummary fleet;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fallback = ColoredBox(
      color: tokens.domainColors.command.soft,
      child: Center(
        child: Text(
          fleet.sid.characters.take(2).toString().toUpperCase(),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: tokens.domainColors.command.foreground),
        ),
      ),
    );
    return Container(
      width: 76,
      height: 76,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(
          color: tokens.surfaces.raised.border,
          width: tokens.stroke.regular,
        ),
        borderRadius: tokens.shape.medium,
      ),
      child: fleet.logoUrl == null
          ? fallback
          : Image.network(
              fleet.logoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _OfficialRankLine extends StatelessWidget {
  const _OfficialRankLine({required this.fleet});

  final OfficialFleetSummary fleet;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final rankName =
        fleet.officialRankName ?? strings.text('officialFleet.rank.unknown');
    final rank = fleet.officialRankValue;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 1; index <= 5; index++) ...[
          Container(
            width: 4,
            height: 13,
            decoration: BoxDecoration(
              color: (rank ?? 0) >= index
                  ? tokens.domainColors.command.foreground
                  : tokens.surfaces.panel.border,
              borderRadius: tokens.shape.small,
            ),
          ),
          if (index < 5) SizedBox(width: tokens.space.xxs),
        ],
        SizedBox(width: tokens.space.sm),
        Flexible(
          child: Text(
            '$rankName · ${rank == null ? '—' : '$rank★'}',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: tokens.domainColors.command.foreground),
          ),
        ),
      ],
    );
  }
}

class _IdentityFact extends StatelessWidget {
  const _IdentityFact({
    required this.icon,
    required this.label,
    required this.color,
  });

  final StarBridgeIconSemantic icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.65)),
        borderRadius: tokens.shape.small,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StarBridgeIcon(icon, size: tokens.icons.small, color: color),
          SizedBox(width: tokens.space.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetailsUnavailable extends StatelessWidget {
  const _ProfileDetailsUnavailable();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: const Key('official-fleet-profile-details-unavailable'),
      role: SurfaceRole.panel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.officialFleet,
            color: tokens.domainColors.recon.foreground,
          ),
          SizedBox(width: tokens.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('officialFleet.profile.unavailable.title'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: tokens.space.xs),
                Text(
                  strings.text('officialFleet.profile.unavailable.body'),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrativeSurface extends StatelessWidget {
  const _NarrativeSurface({required this.profile});

  final OfficialFleetProfileDetails profile;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: const Key('official-fleet-profile-narrative'),
      role: SurfaceRole.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text('officialFleet.profile.about'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tokens.space.md),
          if (profile.rsiDescription case final description?)
            _NarrativeBlock(
              key: const Key('official-fleet-profile-rsi-description'),
              title: strings.text('officialFleet.profile.rsiDescription'),
              body: description,
              color: tokens.domainColors.command.foreground,
            ),
          if (profile.rsiDescription != null &&
              profile.scmSupplementalDescription != null)
            SizedBox(height: tokens.space.lg),
          if (profile.scmSupplementalDescription case final description?)
            _NarrativeBlock(
              key: const Key('official-fleet-profile-scm-description'),
              title: strings.text('officialFleet.profile.scmDescription'),
              body: description,
              color: tokens.domainColors.recon.foreground,
            ),
          if (!profile.hasNarrative)
            Text(
              strings.text('officialFleet.profile.noDescription'),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _NarrativeBlock extends StatelessWidget {
  const _NarrativeBlock({
    required this.title,
    required this.body,
    required this.color,
    super.key,
  });

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: tokens.shape.small,
          ),
        ),
        SizedBox(width: tokens.space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: color),
              ),
              SizedBox(height: tokens.space.xs),
              SelectableText(
                body,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileFacts extends StatelessWidget {
  const _ProfileFacts({required this.profile});

  final OfficialFleetProfileDetails profile;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final focus = _FocusAndTags(profile: profile);
    final attributes = _OrganizationAttributes(profile: profile);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              focus,
              if (profile.hasAttributes) ...[
                SizedBox(height: tokens.space.md),
                attributes,
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: focus),
              if (profile.hasAttributes) ...[
                SizedBox(width: tokens.space.md),
                Expanded(flex: 2, child: attributes),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FocusAndTags extends StatelessWidget {
  const _FocusAndTags({required this.profile});

  final OfficialFleetProfileDetails profile;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text('officialFleet.profile.focus'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tokens.space.md),
          if (profile.hasFocus)
            Wrap(
              spacing: tokens.space.sm,
              runSpacing: tokens.space.sm,
              children: [
                if (profile.primaryFocusLabel case final label?)
                  _LabeledValue(
                    caption: strings.text('officialFleet.profile.primaryFocus'),
                    value: label,
                    color: tokens.domainColors.command.foreground,
                  ),
                if (profile.secondaryFocusLabel case final label?)
                  _LabeledValue(
                    caption: strings.text(
                      'officialFleet.profile.secondaryFocus',
                    ),
                    value: label,
                    color: tokens.domainColors.recon.foreground,
                  ),
              ],
            )
          else
            Text(
              strings.text('officialFleet.profile.focusUnavailable'),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          if (profile.tags.isNotEmpty) ...[
            SizedBox(height: tokens.space.lg),
            Text(
              strings.text('officialFleet.profile.tags'),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
            SizedBox(height: tokens.space.sm),
            Wrap(
              spacing: tokens.space.sm,
              runSpacing: tokens.space.sm,
              children: [
                for (final tag in profile.tags) _NeutralTag(label: tag),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LabeledValue extends StatelessWidget {
  const _LabeledValue({
    required this.caption,
    required this.value,
    required this.color,
  });

  final String caption;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      constraints: const BoxConstraints(minWidth: 176),
      padding: EdgeInsets.all(tokens.space.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: BorderDirectional(
          start: BorderSide(color: color, width: tokens.stroke.strong),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.xs),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _NeutralTag extends StatelessWidget {
  const _NeutralTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.surfaces.panel.border),
        borderRadius: tokens.shape.small,
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _OrganizationAttributes extends StatelessWidget {
  const _OrganizationAttributes({required this.profile});

  final OfficialFleetProfileDetails profile;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final attributes = <(String, String)>[
      if (profile.languageLabels.isNotEmpty)
        (
          strings.text('officialFleet.profile.languages'),
          profile.languageLabels.join(' · '),
        ),
      if (profile.organizationModelLabel case final value?)
        (strings.text('officialFleet.profile.model'), value),
      if (profile.commitmentLabel case final value?)
        (strings.text('officialFleet.profile.commitment'), value),
      if (profile.roleplayLabel case final value?)
        (strings.text('officialFleet.profile.roleplay'), value),
      if (profile.archetypeLabel case final value?)
        (strings.text('officialFleet.profile.archetype'), value),
    ];
    return StarBridgeSurface(
      key: const Key('official-fleet-profile-attributes'),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text('officialFleet.profile.attributes'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tokens.space.sm),
          for (var index = 0; index < attributes.length; index++)
            _AttributeRow(
              label: attributes[index].$1,
              value: attributes[index].$2,
              showDivider: index < attributes.length - 1,
            ),
        ],
      ),
    );
  }
}

class _AttributeRow extends StatelessWidget {
  const _AttributeRow({
    required this.label,
    required this.value,
    required this.showDivider,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: tokens.surfaces.panel.border,
                  width: tokens.stroke.hairline,
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
