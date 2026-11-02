import '../../shared/clock_field.dart';
import 'exec_hangar_motion_controls.dart';
import 'exec_hangar_waiting.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/icons/menu_bridge_glyph.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'exec_hangar_port.dart';
import 'exec_hangar_overview.dart';

String execHangarDuration(BuildContext context, Duration value) {
  final en = Localizations.localeOf(context).languageCode != 'zh';
  final tw = Localizations.localeOf(context).countryCode == 'TW';
  final seconds = (value.inMilliseconds / 1000).ceil().clamp(0, 999999);
  if (seconds < 60) return en ? '${seconds}s' : '$seconds 秒';
  final minutes = (seconds / 60).ceil();
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return en ? '${minutes}m' : '$minutes ${tw ? '分鐘' : '分钟'}';
  return en
      ? '${minutes ~/ 60}h${rest == 0 ? '' : ' ${rest}m'}'
      : '${minutes ~/ 60} ${tw ? '小時' : '小时'}${rest == 0 ? '' : ' $rest ${tw ? '分鐘' : '分钟'}'}';
}

final class ExecHangarMonitorPanel extends StatefulWidget {
  const ExecHangarMonitorPanel({
    super.key,
    required this.snapshot,
    required this.now,
    required this.busy,
    required this.canStart,
    required this.onCommand,
    this.dirty = false,
    this.experience,
    this.previewRules,
  });
  final ExecHangarSnapshot? snapshot;
  final DateTime? now;
  final bool busy, canStart;
  final bool dirty;
  final ExecHangarExperiencePort? experience;
  final ExecHangarReminders? previewRules;
  final void Function(ExecHangarAction action, int minutes, bool onlyNext)
  onCommand;
  @override
  State<ExecHangarMonitorPanel> createState() => _ExecHangarMonitorPanelState();
}

final class _ExecHangarMonitorPanelState extends State<ExecHangarMonitorPanel> {
  int _duration = 60;
  bool _onlyNext = false;
  bool _editing = false,
      _previewBusy = false,
      _previewFailed = false,
      _testing = false;
  String? _testState;
  ExecHangarSnapshot? _preview;
  int _previewEpoch = 0;
  InteractionSource _previewSource = InteractionSource.programmatic;
  InteractionSource _testSource = InteractionSource.programmatic;
  int _testRevision = 0;
  final _hours = TextEditingController(text: '1'),
      _minutes = TextEditingController(text: '0');
  final _form = GlobalKey<FormState>();
  String t(String key) => AppStrings.of(context).text('execHangar.$key');
  String time(DateTime d) {
    final local = d.toLocal();
    String two(int n) => '$n'.padLeft(2, '0');
    final clock =
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    final today = widget.now?.toLocal();
    return today == null ||
            local.year != today.year ||
            local.month != today.month ||
            local.day != today.day
        ? '${two(local.month)}/${two(local.day)} $clock'
        : clock;
  }

  /// One custom-duration list backed by its text controller; a saved value
  /// off the presets stays listed. The total is checked on the minutes.
  Widget _durationPart(
    String id,
    TextEditingController controller,
    List<int> presets,
    String label,
    String Function(int) text,
  ) {
    final current = int.tryParse(controller.text);
    final values = [
      ...presets,
      if (current != null &&
          current >= 0 &&
          current <= presets.last + 4 &&
          !presets.contains(current))
        current,
    ]..sort();
    return StarBridgeSelectFormField<int>(
      identity: id,
      controlKey: Key(id),
      initialValue: values.contains(current) ? current : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final v in values)
          DropdownMenuItem(value: v, child: Text(text(v))),
      ],
      validator: (_) {
        final h = int.tryParse(_hours.text), m = int.tryParse(_minutes.text);
        return h != null && m != null && h * 60 + m >= 1 && h * 60 + m <= 1440
            ? null
            : t('durationRange');
      },
      onChanged: widget.busy
          ? null
          : (v) {
              if (v == null) return;
              setState(() => controller.text = '$v');
            },
    );
  }

  int get _minutesValue => _duration == 0
      ? (int.tryParse(_hours.text) ?? -1440) * 60 +
            (int.tryParse(_minutes.text) ?? -1440)
      : _duration;
  String get _rulesKey =>
      '${widget.previewRules?.wire}|${widget.snapshot?.revision}|${widget.snapshot?.reliable}';
  @override
  void initState() {
    super.initState();
    if (widget.snapshot?.reminders.enabled == true &&
        widget.snapshot?.plan?.endsAt == null) {
      _duration = -1;
    }
    _hours.addListener(_queuePreview);
    _minutes.addListener(_queuePreview);
    _queuePreview();
  }

  @override
  void didUpdateWidget(covariant ExecHangarMonitorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ('${oldWidget.previewRules?.wire}|${oldWidget.snapshot?.revision}|${oldWidget.snapshot?.reliable}' !=
        _rulesKey) {
      _queuePreview();
    }
  }

  void _queuePreview({
    InteractionSource source = InteractionSource.programmatic,
  }) {
    final epoch = ++_previewEpoch;
    _preview = null;
    _previewFailed = false;
    final rules = widget.previewRules, experience = widget.experience;
    _previewBusy =
        experience != null &&
        rules != null &&
        widget.canStart &&
        (_duration != 0 ||
            (int.tryParse(_hours.text) ?? -1) >= 0 &&
                (int.tryParse(_minutes.text) ?? -1) >= 0 &&
                (int.tryParse(_minutes.text) ?? 60) < 60) &&
        (_minutesValue == -1 || _minutesValue >= 1 && _minutesValue <= 1440) &&
        rules.beforeOpenMinutes >= 1 &&
        rules.beforeOpenMinutes <= 120 &&
        rules.beforeCloseMinutes >= 1 &&
        rules.beforeCloseMinutes <= 120;
    if (!_previewBusy) {
      if (mounted) setState(() {});
      return;
    }
    _previewSource = source;
    unawaited(
      Future<void>.microtask(() async {
        if (!mounted || epoch != _previewEpoch) return;
        try {
          final result = await experience!.preview(
            rules!,
            _minutesValue,
            _duration != -1 && _onlyNext,
          );
          if (mounted && epoch == _previewEpoch) {
            setState(() => _preview = result);
          }
        } catch (_) {
          if (mounted && epoch == _previewEpoch) {
            setState(() => _previewFailed = true);
          }
        } finally {
          if (mounted && epoch == _previewEpoch) {
            setState(() => _previewBusy = false);
          }
        }
      }),
    );
    if (mounted) setState(() {});
  }

  Future<void> _test() async {
    _testSource = captureStarBridgeActivationSource()();
    _testRevision++;
    setState(() {
      _testing = true;
      _testState = null;
    });
    try {
      final result = await widget.experience!.testReminder();
      if (mounted) setState(() => _testState = result.deliveryState);
    } catch (_) {
      if (mounted) setState(() => _testState = 'failed');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    ++_previewEpoch;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.snapshot?.plan, now = widget.now;
    final expired =
        plan?.endsAt != null && now != null && now.isAfter(plan!.endsAt!);
    final complete =
        plan?.onlyNext == true &&
        plan?.target != null &&
        now != null &&
        now.isAfter(plan!.target!);
    final active = plan?.active == true && !expired && !complete;
    final next = plan?.next;
    final outside = plan?.outside;
    final waiting = plan?.waiting;
    final game = widget.snapshot?.monitoringSource == 'game';
    final legacy =
        !game &&
        widget.snapshot?.reminders.enabled == true &&
        plan?.endsAt == null;
    final state = complete
        ? 'monitorComplete'
        : expired
        ? 'monitorExpired'
        : active
        ? 'monitorActive'
        : 'monitorStopped';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(
            game
                ? 'gameMonitor'
                : legacy
                ? 'continuousMonitor'
                : 'monitor',
          ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          t('background'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.tokens.colors.textSecondary),
        ),
        const SizedBox(height: 10),
        Text(
          game
              ? t(
                  widget.snapshot?.reliable == true
                      ? 'autoGameWatching'
                      : 'autoGameConfigPaused',
                )
              : legacy
              ? t('monitorContinuous')
              : '${t(state)}${active && plan?.endsAt != null ? ' · ${t('until')} ${time(plan!.endsAt!)}' : ''}',
          key: const Key('exec-monitor-state'),
          style: TextStyle(
            color: active || legacy
                ? context.tokens.colors.success
                : context.tokens.colors.textSecondary,
          ),
        ),
        if (widget.snapshot?.reminders.autoDuringGame == true && !game)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              t(
                widget.snapshot?.monitoringSource == 'manual'
                    ? 'autoGameManual'
                    : switch (widget.snapshot?.gameMonitoringState) {
                        'paused' => 'autoGamePaused',
                        'unknown' => 'autoGameUnknown',
                        'noRules' => 'autoGameNoRules',
                        _ => 'autoGameWaiting',
                      },
              ),
              key: const Key('exec-auto-game-state'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (active && next != null && now != null && next.due.isAfter(now)) ...[
          const SizedBox(height: 6),
          Text(
            '${t('nextReminderAt')} ${time(next.due)} · ${next.kind == 'leave'
                ? t('leaveRule')
                : next.boundary == next.due
                ? t(next.opening ? 'onOpen' : 'onClose')
                : '${t(next.opening ? 'beforeOpen' : 'beforeClose')} ${execHangarDuration(context, next.boundary.difference(next.due))}'}',
            key: const Key('exec-next-reminder'),
          ),
          Text(
            '${time(next.boundary)} ${t(next.opening ? 'opens' : 'closes')} · ${execHangarCountdown(next.boundary, now)}',
          ),
        ],
        if (active && plan?.state == 'noRules') Text(t('noRules')),
        if (active &&
            next == null &&
            waiting != null &&
            now != null &&
            waiting.boundary.isAfter(now))
          Text(
            '${waiting.opening ? t('nextOpen') : t('nextClose')} ${execHangarDuration(context, waiting.boundary.difference(now))} · ${time(waiting.boundary)}',
            key: const Key('exec-waiting-event'),
          ),
        if (active && plan?.state == 'muted') Text(t('mutedEvent')),
        if (active &&
            plan?.mutedBoundary != null &&
            now != null &&
            plan!.mutedBoundary!.isAfter(now))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ExecHangarMotionButton(
              TextButton(
                key: const Key('exec-restore'),
                onPressed: widget.busy || !widget.canStart
                    ? null
                    : () =>
                          widget.onCommand(ExecHangarAction.restore, 0, false),
                child: Text(t('restoreEvent')),
              ),
            ),
          ),
        if (active && plan?.state == 'noEvent' && outside != null) ...[
          const SizedBox(height: 6),
          Text(
            '${t('noEvent')} · ${outside.opening ? t('opens') : t('closes')} ${time(outside.boundary)}',
            key: const Key('exec-no-event'),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ExecHangarMotionButton(
              OutlinedButton(
                key: const Key('exec-extend'),
                onPressed: widget.busy
                    ? null
                    : () => widget.onCommand(ExecHangarAction.extend, 0, false),
                child: Text(
                  outside.opening ? t('extendOpen') : t('extendClose'),
                ),
              ),
            ),
          ),
        ],
        if (active || legacy)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ExecHangarMotionButton(
              OutlinedButton(
                key: const Key('exec-stop'),
                onPressed: widget.busy
                    ? null
                    : () => widget.onCommand(ExecHangarAction.stop, 0, false),
                child: Text(t(game ? 'stopGameMonitor' : 'stopMonitor')),
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (active && plan?.endsAt != null && plan?.onlyNext != true)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ExecHangarMotionButton(
              TextButton(
                key: const Key('exec-add-hour'),
                onPressed:
                    widget.busy ||
                        !widget.canStart ||
                        (plan?.startedAt != null &&
                            plan!.endsAt!.difference(plan.startedAt!) >=
                                const Duration(hours: 24))
                    ? null
                    : () =>
                          widget.onCommand(ExecHangarAction.addHour, 0, false),
                child: Text(t('addHour')),
              ),
            ),
          ),
        if (active &&
            plan?.onlyNext != true &&
            plan?.endsAt != null &&
            plan?.startedAt != null &&
            plan!.endsAt!.difference(plan.startedAt!) >=
                const Duration(hours: 24))
          Text(t('addHourLimit'), style: Theme.of(context).textTheme.bodySmall),
        if (active || legacy)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ExecHangarMotionButton(
              TextButton.icon(
                key: const Key('exec-adjust'),
                onPressed: widget.busy
                    ? null
                    : () => setState(() => _editing = !_editing),
                icon: StandardIcon(
                  _editing
                      ? StandardIconSemantic.expandLess
                      : StandardIconSemantic.expandMore,
                ),
                label: Text(t('adjustMonitor')),
              ),
            ),
          ),
        if (!(active || legacy) || _editing) ...[
          if (active || legacy)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t('restartHint')),
            ),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StarBridgeSelectFormField<int>(
                  identity: 'exec-monitor-mode',
                  controlKey: const Key('exec-monitor-mode-control'),
                  key: const Key('exec-monitor-mode'),
                  initialValue: _duration,
                  decoration: InputDecoration(
                    labelText: t('monitorMode'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: -1,
                      child: Text(t('continuousMonitor')),
                    ),
                    DropdownMenuItem(value: 60, child: Text(t('oneHour'))),
                    DropdownMenuItem(value: 120, child: Text(t('twoHours'))),
                    DropdownMenuItem(
                      value: 0,
                      child: Text(t('customDuration')),
                    ),
                  ],
                  onChanged: widget.busy
                      ? null
                      : (v) {
                          setState(() => _duration = v!);
                          _queuePreview(
                            source: captureStarBridgeActivationSource()(),
                          );
                        },
                ),
                if (_duration == 0) ...[
                  const SizedBox(height: 12),
                  // Hour and minute presets (user decision 2026-10-22).
                  Row(
                    children: [
                      Expanded(
                        child: _durationPart(
                          'exec-watch-hours',
                          _hours,
                          [for (var h = 0; h <= 24; h++) h],
                          t('hours'),
                          (h) => clockCopy(context, 'hours', {'h': '$h'}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _durationPart(
                          'exec-watch-minutes',
                          _minutes,
                          [for (var m = 0; m < 60; m += 5) m],
                          t('durationMinutes'),
                          (m) => clockCopy(context, 'minutes', {'m': '$m'}),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_duration == -1)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(t('continuousHint')),
                  ),
                if (_duration != -1)
                  execHangarCheckbox(
                    CheckboxListTile(
                      key: const Key('exec-only-next'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(t('onlyNext')),
                      subtitle: Text(
                        t('onlyNextHint'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.tokens.colors.textSecondary,
                        ),
                      ),
                      value: _onlyNext,
                      onChanged: widget.busy
                          ? null
                          : (v) {
                              setState(() => _onlyNext = v!);
                              _queuePreview(
                                source: captureStarBridgeActivationSource()(),
                              );
                            },
                    ),
                  ),
                if (widget.dirty)
                  Text(
                    t('saveBeforeStart'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.tokens.colors.warning),
                  ),
                if (!widget.canStart)
                  Text(
                    t(
                      widget.snapshot?.reliable != true
                          ? 'startPaused'
                          : widget.previewRules?.hasRules == false
                          ? 'startNoRules'
                          : 'startConflict',
                    ),
                  ),
                if (widget.experience != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: _previewBusy
                        ? ExecHangarWaiting(
                            key: ValueKey(('preview', _previewEpoch)),
                            label: t('previewLoading'),
                            source: _previewSource,
                          )
                        : Text(
                            _previewFailed
                                ? t('previewFailed')
                                : _preview?.plan == null
                                ? ''
                                : _preview!.plan!.next != null
                                ? '${t('previewLabel')} · ${_preview!.plan!.endsAt == null ? t('continuousMonitor') : '${t('until')} ${time(_preview!.plan!.endsAt!)}'}\n${t('nextReminderAt')} ${time(_preview!.plan!.next!.due)} · ${t(_preview!.plan!.next!.kind == 'leave'
                                      ? 'leaveRule'
                                      : _preview!.plan!.next!.opening
                                      ? 'opens'
                                      : 'closes')} ${time(_preview!.plan!.next!.boundary)}'
                                : '${t('previewLabel')} · ${t('noEvent')}${_preview!.plan!.outside == null ? '' : '\n${t(_preview!.plan!.outside!.opening ? 'opens' : 'closes')} ${time(_preview!.plan!.outside!.boundary)}'}',
                            key: const Key('exec-preview'),
                          ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ExecHangarMotionButton(
                    FilledButton.icon(
                      key: const Key('exec-start'),
                      onPressed: widget.busy || !widget.canStart
                          ? null
                          : () {
                              if (!_form.currentState!.validate()) return;
                              widget.onCommand(
                                _duration == -1
                                    ? ExecHangarAction.continuous
                                    : ExecHangarAction.start,
                                _duration == 0
                                    ? int.parse(_hours.text) * 60 +
                                          int.parse(_minutes.text)
                                    : _duration,
                                _duration != -1 && _onlyNext,
                              );
                            },
                      icon: const StarBridgeIcon(
                        StarBridgeIconSemantic.reminder,
                        size: 18,
                      ),
                      label: Text(
                        active || legacy
                            ? t('restartMonitor')
                            : t('startMonitor'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (widget.experience != null) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ExecHangarMotionButton(
              TextButton.icon(
                key: const Key('exec-test'),
                onPressed: _testing || widget.busy ? null : _test,
                icon: const MenuGlyphView(MenuGlyph.headphones, size: 18),
                label: Text(t('testReminder')),
              ),
            ),
          ),
          if (_testing)
            ExecHangarWaiting(
              key: ValueKey(('test', _testRevision)),
              label: t('testPending'),
              source: _testSource,
            ),
          if (_testState != null)
            Semantics(
              liveRegion: true,
              child: Text(
                t(switch (_testState) {
                  'submitted' => 'testSubmitted',
                  'soundOnly' => 'testSoundOnly',
                  'windowsDisabled' => 'windowsDisabled',
                  'failed' => 'deliveryFailed',
                  'paused' => 'testNoConfig',
                  'doNotDisturb' => 'testDoNotDisturb',
                  'fullScreen' => 'testFullScreen',
                  'inactiveDesktop' => 'testInactiveDesktop',
                  'quietTime' => 'testQuietTime',
                  'systemBusy' => 'testSystemBusy',
                  'queueFull' => 'testQueueFull',
                  'expired' => 'testExpired',
                  'environmentUnknown' => 'testEnvironmentUnknown',
                  'desktopUnavailable' => 'testDesktopUnavailable',
                  _ => 'testSuppressed',
                }),
              ),
            ),
        ],
      ],
    );
  }
}
