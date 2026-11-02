import 'package:flutter/material.dart';

import '../../shared/time_zone_label.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../gameplay_time/gameplay_time_controller.dart';
import 'personal_profile_models.dart';
import 'personal_profile_collaboration.dart';

class PersonalProfileSectionHeading extends StatelessWidget {
  const PersonalProfileSectionHeading({
    required this.projection,
    required this.showOwnerActions,
    required this.onPreview,
    required this.onEdit,
    required this.onRefresh,
    this.onVisibility,
    super.key,
  });

  final PersonalProfileProjection projection;
  final bool showOwnerActions;
  final VoidCallback onPreview;
  final VoidCallback onEdit;
  final VoidCallback onRefresh;
  final VoidCallback? onVisibility;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final title = Text(
      strings.text('profile.page.title'),
      style: Theme.of(context).textTheme.headlineSmall,
    );
    if (!showOwnerActions) {
      return title;
    }
    final actions = Wrap(
      spacing: tokens.space.sm,
      runSpacing: tokens.space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surfaces.status.fill,
            borderRadius: tokens.shape.small,
          ),
          child: StarBridgeActionRow(
            controlKey: const Key('profile-visibility'),
            semanticLabel: strings.text(projection.visibility.labelKey),
            baseRadius: tokens.shape.radiusSmall,
            onActivate: onVisibility == null ? null : (_, _) => onVisibility!(),
            child: ExcludeSemantics(
              child: _VisibilityBadge(
                visibility: projection.visibility,
                fill: false,
              ),
            ),
          ),
        ),
        StarBridgeTooltip(
          message: strings.text('profile.refresh'),
          excludeFromSemantics: true,
          child: StarBridgeActionButton(
            controlKey: const Key('profile-refresh'),
            semanticLabel: strings.text('profile.refresh'),
            minHeight: tokens.density.controlHeight,
            padding: const EdgeInsets.all(8),
            nativeStyle:
                (IconButtonTheme.of(context).style ?? const ButtonStyle())
                    .copyWith(
                      padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
                    ),
            onActivate: projection.operation == PersonalProfileOperation.none
                ? (_) => onRefresh()
                : null,
            child: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
          ),
        ),
        if (projection.local == null)
          StarBridgeActionButton(
            controlKey: const Key('profile-preview'),
            onActivate: (_) => onPreview(),
            child: _ProfileActionLabel(
              icon: StarBridgeIconSemantic.publicProfile,
              label: strings.text('profile.preview.action'),
            ),
          ),
        StarBridgeActionButton(
          controlKey: const Key('profile-edit'),
          onActivate: projection.canEdit ? (_) => onEdit() : null,
          child: _ProfileActionLabel(
            icon: StarBridgeIconSemantic.edit,
            label: strings.text(
              projection.local?.needsCreation == true
                  ? 'profile.local.create'
                  : 'profile.edit.action',
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 780) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              SizedBox(height: tokens.space.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: actions,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: title),
            SizedBox(width: tokens.space.lg),
            actions,
          ],
        );
      },
    );
  }
}

class PersonalProfileVisitorPreviewBanner extends StatelessWidget {
  const PersonalProfileVisitorPreviewBanner({required this.onExit, super.key});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.selected,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.lg,
        vertical: tokens.space.md,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final message = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarBridgeIcon(
                StarBridgeIconSemantic.publicProfile,
                size: tokens.icons.medium,
                color: tokens.colors.accent,
              ),
              SizedBox(width: tokens.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text('profile.preview.title'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      strings.text('profile.preview.body'),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          );
          final exit = StarBridgeActionButton(
            controlKey: const Key('profile-preview-exit'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (_) => onExit(),
            child: Text(strings.text('profile.preview.exit')),
          );
          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                message,
                SizedBox(height: tokens.space.sm),
                Align(alignment: AlignmentDirectional.centerEnd, child: exit),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: message),
              SizedBox(width: tokens.space.md),
              exit,
            ],
          );
        },
      ),
    );
  }
}

class _ProfileActionLabel extends StatelessWidget {
  const _ProfileActionLabel({required this.icon, required this.label});
  final StarBridgeIconSemantic icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      StarBridgeIcon(icon),
      const SizedBox(width: 8),
      Flexible(child: Text(label)),
    ],
  );
}

class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({required this.visibility, this.fill = true});

  final PersonalProfileVisibility visibility;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final color = switch (visibility) {
      PersonalProfileVisibility.everyone => tokens.colors.success,
      PersonalProfileVisibility.friendsAndMainFleet ||
      PersonalProfileVisibility.friendsFleetAndOrganizations ||
      PersonalProfileVisibility.friendsOnly => tokens.colors.stateAccent,
      PersonalProfileVisibility.onlyMe => tokens.colors.textSecondary,
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        color: fill ? tokens.surfaces.status.fill : null,
        borderRadius: tokens.shape.small,
        border: Border.all(
          color: visibility == PersonalProfileVisibility.onlyMe
              ? tokens.surfaces.status.border
              : color,
          width: tokens.stroke.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.publicProfile,
            size: tokens.icons.small,
            color: color,
          ),
          SizedBox(width: tokens.space.xs),
          Flexible(
            child: Text(
              strings.text(visibility.labelKey),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class PersonalProfileSummaryStrip extends StatelessWidget {
  const PersonalProfileSummaryStrip({
    required this.projection,
    this.gameplayTime,
    this.includeLocalTime = true,
    super.key,
  });

  final PersonalProfileProjection projection;
  final GameplayTimeController? gameplayTime;
  final bool includeLocalTime;

  @override
  Widget build(BuildContext context) {
    if (gameplayTime case final controller?) {
      return ValueListenableBuilder<GameplayTimeView>(
        valueListenable: controller,
        builder: (context, state, _) => _buildSummary(context, state),
      );
    }
    return _buildSummary(context, null);
  }

  Widget _buildSummary(BuildContext context, GameplayTimeView? gameplay) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    // Local accounting is an owner-only observation, never evidence of upload.
    // Imported history is already included in seconds; do not add it again.
    final localSeconds = includeLocalTime && gameplay?.visible == true
        ? gameplay?.seconds
        : null;
    final accountMinutes = projection.local?.remoteAvailable == false
        ? null
        : projection.gameplayMinutes;
    final accountTime = accountMinutes == null
        ? strings.text(
            includeLocalTime
                ? 'gameplay.remoteUnavailable'
                : 'gameplay.visitorUnavailable',
          )
        : _formatPlaytime(context, accountMinutes);
    final items = <Widget>[
      _SummaryMetric(
        icon: StarBridgeIconSemantic.schedule,
        colorRole: DomainColorRole.recon,
        labelKey: 'profile.availability.title',
        value: _formatAvailability(context, projection.availabilityWindows),
        detail:
            '${AppStrings.of(context).text('profile.availability.timeZone')} '
            '${timeZoneLabel(context, projection.timeZoneLabel)}',
      ),
      if (gameplay?.showOnProfile != false)
        _SummaryMetric(
          icon: StarBridgeIconSemantic.playtime,
          colorRole: DomainColorRole.logistics,
          labelKey: localSeconds == null
              ? 'gameplay.remoteTotal'
              : 'gameplay.localTotal',
          value: localSeconds == null
              ? accountTime
              : _formatPlaytime(context, localSeconds ~/ 60),
          detail: localSeconds == null
              ? null
              : [
                  if (gameplay!.historicalSeconds > 0)
                    '${strings.text('gameplay.importedTotal')}: '
                        '${_formatPlaytime(context, gameplay.historicalSeconds ~/ 60)}',
                  '${strings.text('gameplay.remoteTotal')}: $accountTime',
                ].join('\n'),
        ),
      _SummaryMetric(
        icon: StarBridgeIconSemantic.activity,
        colorRole: DomainColorRole.medical,
        labelKey: 'profile.activity.title',
        value: AppStrings.of(context)
            .text('profile.activity.${projection.activityRhythm.name}'),
      ),
    ];
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      fillOpacity: 0.84,
      padding: EdgeInsets.all(tokens.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StarBridgeIcon(
                StarBridgeIconSemantic.schedule,
                size: tokens.icons.medium,
                color: tokens.colors.textSecondary,
              ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Text(
                  AppStrings.of(context).text('profile.collaboration.title'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space.md),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      items[index],
                      if (index != items.length - 1)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: tokens.space.md,
                          ),
                          child: Divider(
                            height: tokens.stroke.hairline,
                            color: tokens.surfaces.panel.border,
                          ),
                        ),
                    ],
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      Expanded(child: items[index]),
                      if (index != items.length - 1)
                        VerticalDivider(
                          width: tokens.space.xl,
                          thickness: tokens.stroke.hairline,
                          color: tokens.surfaces.panel.border,
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatAvailability(
    BuildContext context,
    List<PersonalProfileAvailabilityWindow> windows,
  ) {
    return ProfileCollaboration.summary(context, windows);
  }

  String _formatPlaytime(BuildContext context, int totalMinutes) {
    final strings = AppStrings.of(context);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (strings.locale.languageCode == 'en') {
      return '$hours ${strings.text('profile.playtime.hours')} '
          '$minutes ${strings.text('profile.playtime.minutes')}';
    }
    return '$hours${strings.text('profile.playtime.hours')} '
        '$minutes${strings.text('profile.playtime.minutes')}';
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.colorRole,
    required this.labelKey,
    required this.value,
    this.detail,
  });

  final StarBridgeIconSemantic icon;
  final DomainColorRole colorRole;
  final String labelKey;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final colors = tokens.domainColors.resolve(colorRole);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: tokens.space.xl,
          height: tokens.stroke.strong,
          decoration: BoxDecoration(
            color: colors.foreground,
            borderRadius: tokens.shape.pill,
          ),
        ),
        SizedBox(height: tokens.space.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StarBridgeIcon(
              icon,
              size: tokens.icons.medium,
              color: colors.foreground,
            ),
            SizedBox(width: tokens.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text(labelKey),
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                  SizedBox(height: tokens.space.xs),
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                  if (detail case final detail?) ...[
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
