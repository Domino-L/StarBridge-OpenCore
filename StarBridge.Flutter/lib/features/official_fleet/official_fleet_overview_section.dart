import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_models.dart';
import 'official_fleet_overview_models.dart';
import 'official_fleet_overview_module.dart';

class OfficialFleetOverviewSection extends StatefulWidget {
  const OfficialFleetOverviewSection({
    required this.sourceRef,
    required this.module,
    required this.onOpenSection,
    super.key,
  });

  final String sourceRef;
  final OfficialFleetOverviewModule module;
  final ValueChanged<OfficialFleetWorkspaceSection> onOpenSection;

  @override
  State<OfficialFleetOverviewSection> createState() =>
      _OfficialFleetOverviewSectionState();
}

class _OfficialFleetOverviewSectionState
    extends State<OfficialFleetOverviewSection> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.module.open(widget.sourceRef));
  }

  @override
  void didUpdateWidget(covariant OfficialFleetOverviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceRef != widget.sourceRef ||
        oldWidget.module != widget.module) {
      unawaited(widget.module.open(widget.sourceRef));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OfficialFleetOverviewProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        final tokens = context.tokens;
        return Column(
          key: const Key('official-fleet-overview'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStrings.of(context).text('officialFleet.overview.title'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.space.xs),
            Text(
              AppStrings.of(context).text('officialFleet.overview.body'),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
            SizedBox(height: tokens.space.lg),
            switch (projection.availability) {
              OfficialFleetOverviewAvailability.idle ||
              OfficialFleetOverviewAvailability.loading =>
                const _OverviewLoading(),
              OfficialFleetOverviewAvailability.unavailable =>
                _OverviewUnavailable(
                  failureKey:
                      projection.failureKey ??
                      'officialFleet.overview.error.unavailable',
                  onRetry: widget.module.refresh,
                  onOpenOperations: () => widget.onOpenSection(
                    OfficialFleetWorkspaceSection.operations,
                  ),
                ),
              OfficialFleetOverviewAvailability.available => _OverviewContent(
                projection: projection,
                onOpenSection: widget.onOpenSection,
              ),
            },
          ],
        );
      },
    );
  }
}

class _OverviewLoading extends StatelessWidget {
  const _OverviewLoading();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Row(
        children: [
          SizedBox.square(
            dimension: tokens.icons.medium,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: tokens.space.md),
          Text(AppStrings.of(context).text('officialFleet.overview.loading')),
        ],
      ),
    );
  }
}

class _OverviewUnavailable extends StatelessWidget {
  const _OverviewUnavailable({
    required this.failureKey,
    required this.onRetry,
    required this.onOpenOperations,
  });

  final String failureKey;
  final Future<void> Function() onRetry;
  final VoidCallback onOpenOperations;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StarBridgeSurface(
          key: const Key('official-fleet-overview-unavailable'),
          role: SurfaceRole.raised,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarBridgeIcon(
                StarBridgeIconSemantic.warning,
                color: tokens.colors.warning,
              ),
              SizedBox(width: tokens.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.of(context)
                          .text('officialFleet.overview.unavailable.title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: tokens.space.xs),
                    Text(
                      AppStrings.of(context).text(failureKey),
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                    SizedBox(height: tokens.space.md),
                    OutlinedButton.icon(
                      key: const Key('official-fleet-overview-retry'),
                      onPressed: () => unawaited(onRetry()),
                      icon: const StarBridgeIcon(
                        StarBridgeIconSemantic.refresh,
                      ),
                      label: Text(
                        AppStrings.of(context)
                            .text('officialFleet.overview.retry'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.space.md),
        _OperationsEntry(onOpen: onOpenOperations),
      ],
    );
  }
}

class _OverviewContent extends StatelessWidget {
  const _OverviewContent({
    required this.projection,
    required this.onOpenSection,
  });

  final OfficialFleetOverviewProjection projection;
  final ValueChanged<OfficialFleetWorkspaceSection> onOpenSection;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnnouncementPanel(announcement: projection.announcement),
        SizedBox(height: tokens.space.md),
        _FleetSnapshotPanel(
          metrics: projection.metrics!,
          observedAtUtc: projection.observedAtUtc,
          onOpenSection: onOpenSection,
        ),
        SizedBox(height: tokens.space.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final tasks = _TasksPanel(
              tasks: projection.tasks.take(3).toList(growable: false),
              onOpenSection: onOpenSection,
            );
            final operations = _OperationsEntry(
              onOpen: () =>
                  onOpenSection(OfficialFleetWorkspaceSection.operations),
            );
            if (constraints.maxWidth < 820) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tasks,
                  SizedBox(height: tokens.space.md),
                  operations,
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 2, child: tasks),
                  SizedBox(width: tokens.space.md),
                  Expanded(child: operations),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AnnouncementPanel extends StatelessWidget {
  const _AnnouncementPanel({required this.announcement});

  final OfficialFleetOverviewAnnouncement? announcement;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final command = tokens.domainColors.command;
    final value = announcement;
    return StarBridgeSurface(
      key: const Key('official-fleet-current-announcement'),
      role: SurfaceRole.raised,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(
              width: tokens.stroke.strong,
              color: command.foreground,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.space.lg),
          child: value == null
              ? Text(
                  strings.text('officialFleet.overview.announcement.none'),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.colors.textSecondary),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StarBridgeIcon(
                          StarBridgeIconSemantic.notifications,
                          color: command.foreground,
                        ),
                        SizedBox(width: tokens.space.sm),
                        Expanded(
                          child: Text(
                            strings.text(
                              'officialFleet.overview.announcement.title',
                            ),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        if (value.unread)
                          _StatusLabel(
                            label: strings.text(
                              'officialFleet.overview.announcement.unread',
                            ),
                            color: command.foreground,
                          ),
                      ],
                    ),
                    SizedBox(height: tokens.space.md),
                    Text(
                      value.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: tokens.space.xs),
                    Text(
                      value.summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                    SizedBox(height: tokens.space.sm),
                    Text(
                      '${value.authorLabel} · ${_formatUtc(value.publishedAtUtc)}',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _FleetSnapshotPanel extends StatelessWidget {
  const _FleetSnapshotPanel({
    required this.metrics,
    required this.observedAtUtc,
    required this.onOpenSection,
  });

  final OfficialFleetOverviewMetrics metrics;
  final DateTime? observedAtUtc;
  final ValueChanged<OfficialFleetWorkspaceSection> onOpenSection;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final items = <_MetricData>[
      _MetricData(
        labelKey: 'officialFleet.overview.metric.members',
        value: metrics.officialMemberCount,
        icon: StarBridgeIconSemantic.officialFleet,
        color: tokens.domainColors.command.foreground,
        section: OfficialFleetWorkspaceSection.members,
      ),
      _MetricData(
        labelKey: 'officialFleet.overview.metric.online',
        value: metrics.visibleOnlineCount,
        icon: StarBridgeIconSemantic.friends,
        color: tokens.colors.success,
        section: OfficialFleetWorkspaceSection.members,
      ),
      _MetricData(
        labelKey: 'officialFleet.overview.metric.inGame',
        value: metrics.visibleInGameCount,
        icon: StarBridgeIconSemantic.activity,
        color: tokens.domainColors.recon.foreground,
        section: OfficialFleetWorkspaceSection.members,
      ),
      _MetricData(
        labelKey: 'officialFleet.overview.metric.ships',
        value: metrics.sharedRequestableShipCount,
        icon: StarBridgeIconSemantic.hangar,
        color: tokens.domainColors.ship.foreground,
        section: OfficialFleetWorkspaceSection.ships,
      ),
    ];
    return StarBridgeSurface(
      key: const Key('official-fleet-overview-snapshot'),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.text('officialFleet.overview.snapshot.title'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (observedAtUtc != null)
                Text(
                  strings
                      .text('officialFleet.overview.snapshot.updated')
                      .replaceFirst('{time}', _formatUtc(observedAtUtc!)),
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
            ],
          ),
          SizedBox(height: tokens.space.md),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 720) {
                return Wrap(
                  spacing: tokens.space.sm,
                  runSpacing: tokens.space.sm,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: (constraints.maxWidth - tokens.space.sm) / 2,
                        child: _Metric(
                          data: item,
                          onPressed: () => onOpenSection(item.section),
                        ),
                      ),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      Expanded(
                        child: _Metric(
                          data: items[index],
                          onPressed: () => onOpenSection(items[index].section),
                        ),
                      ),
                      if (index != items.length - 1)
                        VerticalDivider(
                          width: tokens.space.lg,
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
}

class _MetricData {
  const _MetricData({
    required this.labelKey,
    required this.value,
    required this.icon,
    required this.color,
    required this.section,
  });

  final String labelKey;
  final int value;
  final StarBridgeIconSemantic icon;
  final Color color;
  final OfficialFleetWorkspaceSection section;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.data, required this.onPressed});

  final _MetricData data;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onPressed,
      borderRadius: tokens.shape.small,
      child: Padding(
        padding: EdgeInsets.all(tokens.space.sm),
        child: Row(
          children: [
            StarBridgeIcon(data.icon, color: data.color),
            SizedBox(width: tokens.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${data.value}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: data.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    AppStrings.of(context).text(data.labelKey),
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ],
              ),
            ),
            StarBridgeIcon(
              StarBridgeIconSemantic.forward,
              size: tokens.icons.small,
              color: tokens.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _TasksPanel extends StatelessWidget {
  const _TasksPanel({required this.tasks, required this.onOpenSection});

  final List<OfficialFleetOverviewTask> tasks;
  final ValueChanged<OfficialFleetWorkspaceSection> onOpenSection;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: const Key('official-fleet-overview-tasks'),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text('officialFleet.overview.tasks.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            strings.text('officialFleet.overview.tasks.body'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.sm),
          if (tasks.isEmpty)
            Text(
              strings.text('officialFleet.overview.tasks.empty'),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            )
          else
            for (var index = 0; index < tasks.length; index++) ...[
              _TaskRow(
                task: tasks[index],
                onPressed: () =>
                    onOpenSection(_workspaceSection(tasks[index].destination)),
              ),
              if (index != tasks.length - 1)
                Divider(color: tokens.surfaces.panel.border),
            ],
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onPressed});

  final OfficialFleetOverviewTask task;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      key: Key('official-fleet-overview-task-${task.id}'),
      onTap: onPressed,
      borderRadius: tokens.shape.small,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StarBridgeIcon(
              StarBridgeIconSemantic.pending,
              color: tokens.colors.warning,
            ),
            SizedBox(width: tokens.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  SizedBox(height: tokens.space.xxs),
                  Text(
                    task.detail,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                  if (task.dueAtUtc != null) ...[
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      AppStrings.of(context)
                          .text('officialFleet.overview.tasks.due')
                          .replaceFirst('{time}', _formatUtc(task.dueAtUtc!)),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: tokens.colors.warning),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: tokens.space.sm),
            StarBridgeIcon(
              StarBridgeIconSemantic.forward,
              size: tokens.icons.small,
              color: tokens.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationsEntry extends StatelessWidget {
  const _OperationsEntry({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final recon = tokens.domainColors.recon;
    return StarBridgeSurface(
      key: const Key('official-fleet-operations-entry'),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.operation,
            color: recon.foreground,
          ),
          SizedBox(height: tokens.space.md),
          Text(
            strings.text('officialFleet.overview.operations.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            strings.text('officialFleet.overview.operations.body'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.md),
          OutlinedButton.icon(
            key: const Key('official-fleet-open-operations'),
            onPressed: onOpen,
            icon: const StarBridgeIcon(StarBridgeIconSemantic.forward),
            label: Text(strings.text('officialFleet.overview.operations.open')),
          ),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.65)),
        borderRadius: tokens.shape.small,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

OfficialFleetWorkspaceSection _workspaceSection(
  OfficialFleetOverviewTaskDestination destination,
) => switch (destination) {
  OfficialFleetOverviewTaskDestination.operations =>
    OfficialFleetWorkspaceSection.operations,
  OfficialFleetOverviewTaskDestination.members =>
    OfficialFleetWorkspaceSection.members,
  OfficialFleetOverviewTaskDestination.ships =>
    OfficialFleetWorkspaceSection.ships,
  OfficialFleetOverviewTaskDestination.broadcasts =>
    OfficialFleetWorkspaceSection.broadcasts,
};

String _formatUtc(DateTime value) {
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute UTC';
}
