import 'exec_hangar_motion_controls.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../common/social_read_activity.dart';
import 'exec_hangar_waiting.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/standard_icon.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'exec_hangar_controller.dart';
import 'exec_hangar_port.dart';
import 'cached_exec_hangar.dart';
import 'exec_hangar_reminder_editor.dart';
import 'exec_hangar_monitor_panel.dart';
import 'exec_hangar_overview.dart';
import 'exec_hangar_schedule.dart';
import 'exec_hangar_surface.dart';
import 'exec_hangar_save_bar.dart';
import '../../platform/window/menu_window_preferences.dart';
import 'exec_hangar_menu_widget_button.dart';

final class ExecHangarPage extends StatefulWidget {
  const ExecHangarPage({
    super.key,
    this.port,
    this.onBack,
    this.embedded = false,
    this.active = true,
    this.menuPreferences,
  });
  final ExecHangarPort? port;
  final VoidCallback? onBack;

  /// The menu window supplies its own title and chrome.
  final bool embedded;

  /// Hiding a menu pauses presentation reads, never Host-owned monitoring.
  final bool active;
  final MenuWindowPreferencesPort? menuPreferences;
  @override
  ExecHangarPageState createState() => ExecHangarPageState();
}

final class ExecHangarPageState extends State<ExecHangarPage> {
  ExecHangarController? _controller;
  SocialReadActivityBinding? _wait;
  ExecHangarSnapshot? _snapshot;
  final _elapsed = Stopwatch();
  Duration _snapshotAge = Duration.zero;
  Timer? _timer;
  DateTime? _receivedWall;
  int _lastReadSecond = 0;
  bool _dirty = false;
  int _draftRevision = 0;
  ExecHangarReminders _draft = const ExecHangarReminders();
  final _form = GlobalKey<FormState>();
  final _beforeOpen = TextEditingController(text: '5');
  final _beforeClose = TextEditingController(text: '5');
  String t(String key) => AppStrings.of(context).text('execHangar.$key');
  @override
  void initState() {
    super.initState();
    if (widget.port == null) return;
    final cache = widget.port is CachedExecHangar
        ? widget.port as CachedExecHangar
        : null;
    _controller = ExecHangarController(
      widget.port!,
      initialSnapshot: cache?.snapshot,
    );
    _wait = SocialReadActivityBinding(
      _controller!,
      () => _controller!.value.busy,
      initialRead: cache?.snapshot == null,
    );
    _controller!.addListener(_changed);
    _changed();
    if (widget.active &&
        (cache?.fresh != true ||
            cache?.snapshot?.reminders.autoDuringGame == true)) {
      unawaited(_controller!.read());
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !widget.active) return;
      final wall = _receivedWall;
      final jumped =
          wall != null &&
          (DateTime.now().difference(wall).inSeconds -
                      _elapsed.elapsed.inSeconds)
                  .abs() >
              2;
      final snapshot = _snapshot;
      final now = snapshot?.now.add(_snapshotAge + _elapsed.elapsed);
      final crossed =
          snapshot != null &&
          now != null &&
          [
            snapshot.plan?.next?.due,
            snapshot.plan?.endsAt,
            snapshot.plan?.target,
          ].whereType<DateTime>().any(
            (end) => end.isAfter(snapshot.now) && !end.isAfter(now),
          );
      if (jumped ||
          crossed &&
              !_controller!.value.busy &&
              _elapsed.elapsed.inSeconds - _lastReadSecond >= 1 ||
          _elapsed.elapsed.inSeconds - _lastReadSecond >=
              (snapshot?.reminders.autoDuringGame == true ? 5 : 60)) {
        _lastReadSecond = _elapsed.elapsed.inSeconds;
        unawaited(
          runStarBridgeActivation<bool>(
            InteractionSource.programmatic,
            () => _controller!.read(),
          ),
        );
      }
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ExecHangarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && _controller != null) {
      unawaited(
        runStarBridgeActivation<bool>(
          InteractionSource.programmatic,
          () => _controller!.read(),
        ),
      );
    }
  }

  void _changed() {
    if (!mounted) return;
    final snapshot = _controller!.value.snapshot;
    if (!identical(snapshot, _snapshot) && snapshot != null) {
      _snapshot = snapshot;
      _snapshotAge = widget.port is CachedExecHangar
          ? (widget.port as CachedExecHangar).age
          : Duration.zero;
      _elapsed
        ..reset()
        ..start();
      _receivedWall = DateTime.now();
      _lastReadSecond = -_snapshotAge.inSeconds;
      if (!_dirty) _resetDraft();
    }
    setState(() {});
  }

  void _resetDraft() {
    _draft = _snapshot?.reminders ?? const ExecHangarReminders();
    _draftRevision = _snapshot?.revision ?? 0;
    _beforeOpen.text = '${_draft.beforeOpenMinutes}';
    _beforeClose.text = '${_draft.beforeCloseMinutes}';
    _dirty = false;
  }

  void _toggle({
    bool? onClose,
    bool? onOpen,
    bool? beforeOpen,
    bool? beforeClose,
    bool? leaveWarning,
    bool? autoDuringGame,
  }) => setState(() {
    _dirty = true;
    _draft = ExecHangarReminders(
      enabled: _draft.enabled,
      autoDuringGame: autoDuringGame ?? _draft.autoDuringGame,
      leaveWarning: leaveWarning ?? _draft.leaveWarning,
      onClose: onClose ?? _draft.onClose,
      beforeChange: false,
      onOpen: onOpen ?? _draft.onOpen,
      beforeOpen: beforeOpen ?? _draft.beforeOpen,
      beforeOpenMinutes: _draft.beforeOpenMinutes,
      beforeClose: beforeClose ?? _draft.beforeClose,
      beforeCloseMinutes: _draft.beforeCloseMinutes,
    );
  });
  Future<bool> _save() async {
    if (!_form.currentState!.validate()) return false;
    final desired = ExecHangarReminders(
      enabled: _snapshot!.reminders.enabled,
      autoDuringGame: _draft.autoDuringGame,
      leaveWarning: _draft.leaveWarning,
      onClose: _draft.onClose,
      beforeChange: false,
      onOpen: _draft.onOpen,
      beforeOpen: _draft.beforeOpen,
      beforeOpenMinutes: int.parse(_beforeOpen.text),
      beforeClose: _draft.beforeClose,
      beforeCloseMinutes: int.parse(_beforeClose.text),
    );
    if (await _controller!.save(desired, expectedRevision: _draftRevision) &&
        mounted) {
      setState(_resetDraft);
      return true;
    }
    return false;
  }

  Future<void> _monitor(ExecHangarAction action, int minutes, bool onlyNext) =>
      runStarBridgeActivation<void>(
        captureStarBridgeActivationSource()(),
        () async {
          if (action != ExecHangarAction.stop && _dirty && !await _save()) {
            return;
          }
          final success = await _controller!.monitor(
            action,
            durationMinutes: minutes,
            onlyNext: onlyNext,
          );
          if (success && mounted && action == ExecHangarAction.stop && _dirty) {
            setState(() => _draftRevision = _snapshot!.revision);
          }
        },
      );

  Future<bool> confirmLeave(BuildContext context) async {
    if (!_dirty) return true;
    return await showStarBridgeDialog<bool>(
          context,
          builder: (context) => AlertDialog(
            title: Text(t('unsaved')),
            content: Text(t('unsavedBody')),
            actions: [
              ExecHangarMotionButton(
                TextButton(
                  onPressed: () => dismissStarBridgeDialog<bool>(
                    context,
                    source: captureStarBridgeActivationSource()(),
                    result: false,
                  ),
                  child: Text(t('stay')),
                ),
              ),
              ExecHangarMotionButton(
                TextButton(
                  onPressed: () => dismissStarBridgeDialog<bool>(
                    context,
                    source: captureStarBridgeActivationSource()(),
                    result: true,
                  ),
                  child: Text(t('discard')),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wait?.dispose();
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _beforeOpen.dispose();
    _beforeClose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = _controller?.value ?? const ExecHangarView();
    final snapshot = _snapshot;
    final now = snapshot?.now.add(_snapshotAge + _elapsed.elapsed);
    final phase = now == null
        ? null
        : snapshot!.phases
              .where((p) => !now.isBefore(p.start) && now.isBefore(p.end))
              .firstOrNull;
    final colors = context.tokens.colors;
    final busy = view.busy;
    final reliable =
        snapshot?.reliable == true &&
        snapshot!.fetchedAt != null &&
        now!.difference(snapshot.fetchedAt!) <= const Duration(hours: 6);
    final nextOpen = now == null
        ? null
        : snapshot!.windows.where((w) => w.open.isAfter(now)).firstOrNull?.open;
    final nextChange = phase == null
        ? null
        : phase.open
        ? snapshot!.windows
              .where((w) => !now!.isBefore(w.open) && now.isBefore(w.close))
              .firstOrNull
              ?.close
        : nextOpen;
    final content = Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(
                widget.embedded
                    ? context.tokens.space.md
                    : context.tokens.space.lg,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.onBack != null)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ExecHangarMotionButton(
                            TextButton.icon(
                              onPressed: widget.onBack,
                              icon: const StandardIcon(
                                StandardIconSemantic.arrowBack,
                                size: 18,
                              ),
                              label: Text(
                                AppStrings.of(context).text('tools.back'),
                              ),
                            ),
                          ),
                        ),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!widget.embedded)
                                Text(
                                  t('title'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                              if (!widget.embedded) const SizedBox(height: 6),
                              Text(t('prediction')),
                            ],
                          ),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              if (widget.menuPreferences != null)
                                ExecHangarMenuWidgetButton(
                                  port: widget.menuPreferences!,
                                ),
                              ExecHangarMotionButton(
                                OutlinedButton.icon(
                                  key: const Key('exec-refresh'),
                                  onPressed: busy || _controller == null
                                      ? null
                                      : () => _controller!.read(refresh: true),
                                  icon: const StarBridgeIcon(
                                    StarBridgeIconSemantic.refresh,
                                    size: 18,
                                  ),
                                  label: Text(t('refresh')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (widget.port == null)
                        Text(t('unavailable'))
                      else if (snapshot == null && busy)
                        _waiting()
                      else ...[
                        if (view.failed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              t('failed'),
                              style: TextStyle(color: colors.danger),
                            ),
                          ),
                        if (snapshot?.refreshFailed == true)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(t('offline')),
                          ),
                        Text(
                          snapshot?.version != null
                              ? reliable
                                    ? t('fresh')
                                    : t('stale')
                              : t('noConfig'),
                          style: TextStyle(
                            color: reliable
                                ? colors.textSecondary
                                : colors.warning,
                          ),
                        ),
                        if (phase != null && nextChange != null) ...[
                          SizedBox(height: context.tokens.space.md),
                          ExecHangarSurface(
                            child: ExecHangarOverview(
                              phase: phase,
                              nextChange: nextChange,
                              now: now!,
                            ),
                          ),
                        ],
                        SizedBox(height: context.tokens.space.lg),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final schedule = ExecHangarSurface(
                              child: ExecHangarSchedule(
                                snapshot: snapshot,
                                now: now,
                              ),
                            );
                            if (widget.embedded) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _monitorCard(busy),
                                  SizedBox(height: context.tokens.space.lg),
                                  schedule,
                                  SizedBox(height: context.tokens.space.lg),
                                  _rulesCard(busy),
                                ],
                              );
                            }
                            final reminders = _reminders(busy);
                            if (constraints.maxWidth < 1000) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  schedule,
                                  SizedBox(height: context.tokens.space.lg),
                                  reminders,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 4, child: schedule),
                                SizedBox(width: context.tokens.space.lg),
                                Expanded(flex: 8, child: reminders),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (busy && snapshot != null)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.tokens.space.lg,
                vertical: context.tokens.space.sm,
              ),
              child: _waiting(),
            ),
          if (_dirty)
            ExecHangarSaveBar(
              busy: busy || snapshot == null,
              conflict: snapshot?.revision != _draftRevision,
              onSave: _save,
              onReset: () => setState(_resetDraft),
            ),
        ],
      ),
    );
    return LoadingContentProbe(
      route: '/tools/exec-hangar',
      status: widget.port == null
          ? LoadingContentStatus.unavailable
          : view.busy
          ? (snapshot == null
                ? LoadingContentStatus.waiting
                : LoadingContentStatus.partial)
          : view.failed
          ? (snapshot == null
                ? LoadingContentStatus.failed
                : LoadingContentStatus.partial)
          : snapshot == null
          ? LoadingContentStatus.waiting
          : LoadingContentStatus.data,
      items: snapshot == null ? 0 : 1,
      child: content,
    );
  }

  Widget _reminders(bool busy) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _monitorCard(busy),
      SizedBox(height: context.tokens.space.lg),
      _rulesCard(busy),
    ],
  );

  Widget _waiting() => ExecHangarWaiting(
    key: ValueKey((_controller, _wait!.revision)),
    source: _wait!.source,
    opening: _wait!.opening,
    active: widget.active,
    label: t(_wait!.opening ? 'widgetTimeLoading' : 'waitingResult'),
  );

  Widget _monitorCard(bool busy) => ExecHangarSurface(
    child: ExecHangarMonitorPanel(
      snapshot: _snapshot,
      now: _snapshot?.now.add(_snapshotAge + _elapsed.elapsed),
      busy: busy,
      dirty: _dirty,
      experience: widget.port is ExecHangarExperiencePort
          ? widget.port as ExecHangarExperiencePort
          : null,
      previewRules: ExecHangarReminders(
        enabled: true,
        beforeChange: false,
        onOpen: _draft.onOpen,
        onClose: _draft.onClose,
        beforeOpen: _draft.beforeOpen,
        beforeClose: _draft.beforeClose,
        beforeOpenMinutes: int.tryParse(_beforeOpen.text) ?? 0,
        beforeCloseMinutes: int.tryParse(_beforeClose.text) ?? 0,
        leaveWarning: _draft.leaveWarning,
        autoDuringGame: _draft.autoDuringGame,
      ),
      canStart:
          _snapshot?.reliable == true &&
          _snapshot!.revision == _draftRevision &&
          (_draft.onOpen ||
              _draft.beforeOpen ||
              _draft.beforeClose ||
              _draft.onClose ||
              _draft.leaveWarning),
      onCommand: _monitor,
    ),
  );

  Widget _rulesCard(bool busy) => ExecHangarSurface(
    child: ExecHangarReminderEditor(
      t: t,
      form: _form,
      draft: _draft,
      beforeOpen: _beforeOpen,
      beforeClose: _beforeClose,
      showActions: !_dirty,
      busy: busy || _snapshot == null,
      dirty: _dirty,
      conflict: _dirty && _snapshot?.revision != _draftRevision,
      onToggle: _toggle,
      onEdited: () => setState(() => _dirty = true),
      onSave: _save,
      onReset: () => setState(_resetDraft),
      deliveryState: _snapshot?.deliveryState,
    ),
  );
}
