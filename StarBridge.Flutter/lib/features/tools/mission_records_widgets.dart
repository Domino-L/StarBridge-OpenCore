import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'tools_style.dart';

import 'mission_records_controller.dart';

String missionRecordText(AppStrings strings, String key) =>
    strings.text('missionRecords.$key');

String missionRecordDuration(AppStrings strings, num seconds) {
  final minutes = seconds.toInt() ~/ 60;
  return missionRecordText(strings, minutes >= 60 ? 'hours' : 'minutes')
      .replaceAll('{hours}', '${minutes ~/ 60}')
      .replaceAll('{minutes}', '${minutes >= 60 ? minutes % 60 : minutes}');
}

/// Card label: the count, then every role that has a timed run (user 11-13:
/// show each role's best, not one best). Old hosts without roles keep one best.
const missionRecordLabelSeparator = '\n';

String missionRecordLabel(AppStrings strings, MissionRecordGroup group) {
  String line(String key, num seconds) => missionRecordText(
    strings,
    key,
  ).replaceAll('{duration}', missionRecordDuration(strings, seconds));
  return [
    missionRecordText(strings, 'count').replaceAll('{count}', '${group.count}'),
    if (group.hasRoles) ...[
      if (group.soloFastestSeconds != null)
        line('fastestSolo', group.soloFastestSeconds!),
      if (group.teamFastestSeconds != null)
        line('fastestTeam', group.teamFastestSeconds!),
      if (group.joinedFullFastestSeconds != null)
        line('cardJoinedFull', group.joinedFullFastestSeconds!),
      if (group.joinedPartialFastestSeconds != null)
        line('cardJoinedPartial', group.joinedPartialFastestSeconds!),
    ] else if (group.fastestSeconds != null)
      line('fastest', group.fastestSeconds!),
  ].join(missionRecordLabelSeparator);
}

/// Detail lines: one per role when the host splits them, else the single best.
List<String> missionRecordFastestLines(
  AppStrings strings,
  MissionRecordGroup? group,
) {
  String line(String key, num seconds) => missionRecordText(
    strings,
    key,
  ).replaceAll('{duration}', missionRecordDuration(strings, seconds));
  if (group != null && group.hasRoles) {
    return [
      if (group.soloFastestSeconds != null)
        line('fastestSolo', group.soloFastestSeconds!),
      if (group.teamFastestSeconds != null)
        line('fastestTeam', group.teamFastestSeconds!),
      if (group.joinedFullFastestSeconds != null)
        line('fastestJoinedFull', group.joinedFullFastestSeconds!),
      if (group.joinedPartialFastestSeconds != null)
        line('fastestJoinedPartial', group.joinedPartialFastestSeconds!),
    ];
  }
  return [
    missionRecordText(strings, 'fastest').replaceAll(
      '{duration}',
      group?.fastestSeconds == null
          ? '—'
          : missionRecordDuration(strings, group!.fastestSeconds!),
    ),
  ];
}

String missionRecordDate(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatMediumDate(date.toLocal());

class MissionRecordBadge extends StatelessWidget {
  const MissionRecordBadge(this.group, {super.key});
  final MissionRecordGroup group;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.tokens.colors.success),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          missionRecordLabel(AppStrings.of(context), group),
          key: const Key('mission-record-badge'),
          style: toolNumber(
            context,
            size: 16,
            color: context.tokens.colors.success,
          ),
        ),
      ),
    ),
  );
}

class MissionRecordDetails extends StatelessWidget {
  const MissionRecordDetails(this.group, {super.key});
  final MissionRecordGroup? group;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context), record = group;
    return Column(
      key: const Key('mission-record-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ToolsRule(),
        Text(
          missionRecordText(strings, 'entry'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          missionRecordText(
            strings,
            'count',
          ).replaceAll('{count}', '${record?.count ?? 0}'),
          style: toolNumber(
            context,
            size: 24,
            color: context.tokens.colors.success,
          ),
        ),
        for (final line in missionRecordFastestLines(strings, record))
          Text(line, style: toolNumber(context, size: 24)),
        Text(
          missionRecordText(strings, 'timingNote'),
          key: const Key('mission-record-timing-note'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          '${missionRecordText(strings, 'last')}: ${record == null ? '—' : missionRecordDate(context, record.lastCompletedAt)}',
        ),
      ],
    );
  }
}

/// Shared by both entry points; the modal follows the gameplay history scan.
class MissionRecordsImport extends StatelessWidget {
  const MissionRecordsImport(
    this.controller, {
    super.key,
    this.inline = false,
    this.feedbackOnly = false,
  });
  final MissionRecordsController controller;
  final bool inline, feedbackOnly;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.visible) return const SizedBox.shrink();
      final strings = AppStrings.of(context);
      String t(String key) => missionRecordText(strings, key);
      final result = controller.result;
      String counts(String key) {
        var text = t(key);
        for (final field in [
          'filesScanned',
          'added',
          'alreadyKnown',
          'filesSkipped',
        ]) {
          text = text.replaceAll('{$field}', '${result?[field] ?? 0}');
        }
        return text;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!feedbackOnly && controller.importSupported)
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: const Key('mission-record-import'),
              onActivate: !controller.canImport
                  ? null
                  : (source) async {
                      final operation = controller.startImport();
                      if (controller.busy && context.mounted) {
                        await showStarBridgeDialog<void>(
                          context,
                          source: source,
                          barrierDismissible: false,
                          builder: (_) =>
                              _MissionScanDialog(controller, source: source),
                        );
                      }
                      await operation;
                    },
              child: Text(t('import')),
            ),
          if (!inline &&
              controller.importSupported &&
              !controller.importAvailable &&
              controller.reason != null)
            Text(
              t(controller.reason!),
              key: const Key('mission-record-reason'),
            ),
          if (!inline &&
              controller.importSupported &&
              controller.unclassified > 0 &&
              !controller.busy)
            Text(
              t('reimportHint')
                  .replaceAll('{count}', '${controller.unclassified}'),
              key: const Key('mission-record-reimport-hint'),
            ),
          if (!inline && controller.error != null)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  t(controller.error!),
                  key: const Key('mission-record-error'),
                  style: TextStyle(color: context.tokens.colors.textSecondary),
                ),
                if (controller.error == 'readError')
                  TextButton(
                    onPressed: controller.load,
                    child: Text(t('retry')),
                  ),
              ],
            ),
          if (!inline && result != null)
            Text(
              [
                counts('result'),
                if ((result['filesSkipped'] as num? ?? 0) > 0)
                  counts('skipped'),
              ].join(' · '),
              key: const Key('mission-record-result'),
            ),
        ],
      );
    },
  );
}

class _MissionScanDialog extends StatefulWidget {
  const _MissionScanDialog(this.controller, {required this.source});
  final MissionRecordsController controller;
  final InteractionSource source;
  @override
  State<_MissionScanDialog> createState() => _MissionScanDialogState();
}

class _MissionScanDialogState extends State<_MissionScanDialog> {
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (!widget.controller.busy && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        }
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, progress = c.progress;
    final strings = AppStrings.of(context);
    String t(String key) => missionRecordText(strings, key);
    final total = progress?['bytesTotal'] as num? ?? 0;
    final done = progress?['bytesDone'] as num? ?? 0;
    final phase = c.cancelling
        ? 'cancelling'
        : progress?['phase']?.toString() ?? 'discovering';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            unawaited(c.cancelImport()),
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (popped, _) {
            if (!popped) unawaited(c.cancelImport());
          },
          child: AlertDialog(
            key: const Key('mission-record-scan'),
            scrollable: true,
            title: Text(t('import')),
            content: SizedBox(
              width: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t(phase), key: const Key('mission-record-phase')),
                  SizedBox(height: context.tokens.space.md),
                  _MissionWaiting(
                    source: widget.source,
                    value: total > 0 ? (done / total).clamp(0.0, 1.0) : null,
                  ),
                  SizedBox(height: context.tokens.space.md),
                  Text(
                    t('files')
                        .replaceAll('{done}', '${progress?['filesDone'] ?? 0}')
                        .replaceAll(
                          '{total}',
                          '${progress?['filesTotal'] ?? 0}',
                        ),
                    key: const Key('mission-record-files'),
                  ),
                  if (c.error != null) Text(t(c.error!)),
                ],
              ),
            ),
            actions: [
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('mission-record-cancel'),
                onActivate: c.cancelling ? null : (_) => c.cancelImport(),
                child: Text(t(c.cancelling ? 'cancelling' : 'cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissionWaiting extends StatelessWidget {
  const _MissionWaiting({required this.source, this.value});
  final InteractionSource source;
  final double? value;
  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        return InteractionScope(
          data: data.copyWith(
            reduceMotion:
                data.reduceMotion || source == InteractionSource.keyboard,
          ),
          child: SuiteProgressBar(value: value, phase: ProgressPhase.running),
        );
      },
    ),
  );
}
