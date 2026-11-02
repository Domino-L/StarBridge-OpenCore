import 'exec_hangar_motion_controls.dart';

import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'exec_hangar_port.dart';
import 'exec_hangar_overview.dart';

final class ExecHangarSchedule extends StatefulWidget {
  const ExecHangarSchedule({
    super.key,
    required this.snapshot,
    required this.now,
    this.windows,
  });
  final ExecHangarSnapshot? snapshot;
  final DateTime? now;
  final List<ExecHangarWindow>? windows;
  @override
  State<ExecHangarSchedule> createState() => _ExecHangarScheduleState();
}

final class _ExecHangarScheduleState extends State<ExecHangarSchedule> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens, text = Theme.of(context).textTheme;
    String t(String key) => AppStrings.of(context).text('execHangar.$key');
    final events =
        <({DateTime time, bool opening})>[
              for (final window
                  in widget.windows ??
                      widget.snapshot?.windows ??
                      <ExecHangarWindow>[]) ...[
                (time: window.open, opening: true),
                (time: window.close, opening: false),
              ],
            ]
            .where((e) => widget.now == null || e.time.isAfter(widget.now!))
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    final visible = _expanded ? events : events.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('schedule'), style: text.titleMedium),
        SizedBox(height: tokens.space.xs),
        Text(
          t('localTime'),
          style: text.bodySmall?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(height: tokens.space.md),
        if (events.isEmpty)
          Text(
            t('emptySchedule'),
            style: text.bodyMedium?.copyWith(
              color: tokens.colors.textSecondary,
            ),
          ),
        for (var index = 0; index < visible.length; index++)
          _event(
            context,
            visible[index].time,
            visible[index].opening,
            index == 0,
            index < visible.length - 1,
            t,
          ),
        if (events.length > 6)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ExecHangarMotionButton(
              TextButton.icon(
                key: const Key('exec-expand-schedule'),
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: StandardIcon(
                  _expanded
                      ? StandardIconSemantic.expandLess
                      : StandardIconSemantic.expandMore,
                  size: 18,
                ),
                label: Text(
                  t(_expanded ? 'collapseSchedule' : 'expandSchedule'),
                ),
              ),
            ),
          ),
        if (widget.snapshot?.version != null)
          execHangarDisclosure(
            ExpansionTile(
              key: const Key('exec-calibration-details'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.only(bottom: tokens.space.sm),
              title: Text(
                t('calibrationDetails'),
                style: text.bodySmall?.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${t('version')} ${widget.snapshot!.version} · ${widget.snapshot!.lastModified ?? ''}',
                  style: text.bodySmall,
                ),
                if (widget.snapshot!.fetchedAt != null)
                  Text(
                    '${t('fetched')} ${execHangarTime(widget.snapshot!.fetchedAt!)}',
                    style: text.bodySmall,
                  ),
                if (widget.snapshot!.sourceUrl != null)
                  SelectableText(
                    '${t('source')} ${widget.snapshot!.sourceUrl}',
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _event(
    BuildContext context,
    DateTime time,
    bool opening,
    bool next,
    bool connected,
    String Function(String) t,
  ) {
    final tokens = context.tokens, text = Theme.of(context).textTheme;
    final parts = execHangarTime(time).split(' ');
    final color = opening ? tokens.colors.success : tokens.colors.danger;
    return Semantics(
      label:
          '${next ? '${t('nextEvent')} · ' : ''}${opening ? t('opens') : t('closes')} · ${execHangarTime(time)}',
      child: ExcludeSemantics(
        child: IntrinsicHeight(
          child: Row(
            key: ValueKey('exec-event-${time.millisecondsSinceEpoch}-$opening'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 18,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    if (!next)
                      Positioned(
                        top: 0,
                        height: 15,
                        width: 1,
                        child: ColoredBox(color: tokens.surfaces.panel.border),
                      ),
                    if (connected)
                      Positioned(
                        top: 26,
                        bottom: -10,
                        width: 1,
                        child: ColoredBox(color: tokens.surfaces.panel.border),
                      ),
                    Positioned(
                      top: 15,
                      child: StandardIcon(
                        opening
                            ? StandardIconSemantic.circle
                            : StandardIconSemantic.circleOutline,
                        size: 14,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parts.last,
                        style: text.titleLarge?.copyWith(
                          fontSize: tokens.typography.title * 1.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        parts.first,
                        style: text.bodySmall?.copyWith(
                          color: tokens.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: tokens.space.sm),
              Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      opening ? t('opens') : t('closes'),
                      style: text.titleSmall?.copyWith(color: color),
                    ),
                    if (next)
                      Text(
                        t('nextEvent'),
                        style: text.bodySmall?.copyWith(
                          color: tokens.colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
