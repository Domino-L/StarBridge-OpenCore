import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/image_tool_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';

import '../localization/app_strings.dart';
import '../../features/tools/exec_hangar_overview.dart';
import '../../features/tools/exec_hangar_schedule.dart';
import '../../features/tools/exec_hangar_surface.dart';
import '../../platform/window/menu_exec_hangar_summary.dart';
import '../../platform/window/menu_exec_hangar_game_overlay.dart';
import 'menu_exec_hangar_game_pin.dart';

/// Menu-owned presentation only. Reminder operations remain in the tool page.
final class MenuExecHangarWindow extends StatefulWidget {
  const MenuExecHangarWindow({
    super.key,
    required this.port,
    required this.active,
    required this.pinned,
    this.initial,
    this.onSnapshot,
    this.onPinned,
    this.onSettings,
  });
  final MenuExecHangarSummaryPort port;
  final bool active, pinned;
  final MenuExecHangarSummary? initial;
  final ValueChanged<MenuExecHangarSummary>? onSnapshot;
  final ValueChanged<bool>? onPinned;
  final VoidCallback? onSettings;

  @override
  State<MenuExecHangarWindow> createState() => _WindowState();
}

class _WindowState extends State<MenuExecHangarWindow> {
  MenuExecHangarSummary? _summary;
  final _clock = Stopwatch();
  Timer? _timer;
  bool _busy = false, _failed = false;
  int _lastRead = 0;
  int _request = 0;
  String t(String key) => AppStrings.of(context).text('execHangar.$key');

  @override
  void initState() {
    super.initState();
    _summary = widget.initial;
    _clock.start();
    if (widget.active) unawaited(_read());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !widget.active) return;
      if (_clock.elapsed.inSeconds - _lastRead >= 60) {
        _lastRead = _clock.elapsed.inSeconds;
        unawaited(_read());
      }
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(MenuExecHangarWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active || widget.port != oldWidget.port) {
      _request++;
      _busy = false;
    }
    if (widget.active && (!oldWidget.active || widget.port != oldWidget.port)) {
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    if (_busy || !widget.active) return;
    _busy = true;
    final request = ++_request;
    try {
      final value = await widget.port.read();
      if (!mounted || !widget.active || request != _request) return;
      widget.onSnapshot?.call(value);
      setState(() {
        _summary = value;
        _failed = false;
        _clock.reset();
        _lastRead = 0;
      });
    } on Object {
      if (mounted && widget.active && request == _request) {
        setState(() => _failed = true);
      }
    } finally {
      if (request == _request) _busy = false;
    }
  }

  @override
  void dispose() {
    _request++;
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final now = summary?.now.add(_clock.elapsed);
    final reliable =
        summary?.reliable == true &&
        summary?.fetchedAt != null &&
        !now!.isBefore(summary!.fetchedAt!) &&
        now.difference(summary.fetchedAt!) <= const Duration(hours: 6);
    final phase = summary?.phases
        .where((p) => !now!.isBefore(p.start) && now.isBefore(p.end))
        .firstOrNull;
    final next = phase == null
        ? null
        : phase.open
        ? summary!.windows
              .where((w) => !now!.isBefore(w.open) && now.isBefore(w.close))
              .firstOrNull
              ?.close
        : summary!.windows.where((w) => w.open.isAfter(now!)).firstOrNull?.open;
    return SingleChildScrollView(
      key: const Key('menu-hangar-window'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              StarBridgeActionButton(
                controlKey: const Key('menu-hangar-pin'),
                onActivate: widget.onPinned == null
                    ? null
                    : (_) => widget.onPinned!(!widget.pinned),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox.square(
                      dimension: 18,
                      child: FittedBox(
                        child: ImageToolIcon(ImageToolGlyph.pin),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        t(widget.pinned ? 'widgetUnpin' : 'widgetPin'),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onSettings != null)
                StarBridgeActionButton(
                  controlKey: const Key('menu-hangar-settings'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (_) => widget.onSettings!(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const StarBridgeIcon(
                        StarBridgeIconSemantic.settings,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(t('widgetReminderSettings'))),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.port is MenuExecHangarGameOverlayPort &&
              (widget.port as MenuExecHangarGameOverlayPort)
                  .gameOverlayAvailable) ...[
            MenuExecHangarGamePin(
              port: widget.port as MenuExecHangarGameOverlayPort,
              active: widget.active,
            ),
            const SizedBox(height: 16),
          ],
          if (reliable && phase != null && next != null)
            ExecHangarSurface(
              child: ExecHangarOverview(
                phase: phase,
                nextChange: next,
                now: now,
              ),
            )
          else
            ExecHangarSurface(
              child: Text(
                t(
                  summary == null
                      ? _failed
                            ? 'widgetUnavailable'
                            : 'widgetTimeLoading'
                      : 'widgetStale',
                ),
              ),
            ),
          if (_failed && summary != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t('offline')),
            ),
          const SizedBox(height: 16),
          if (summary != null)
            ExecHangarSurface(
              child: ExecHangarSchedule(
                snapshot: null,
                windows: summary.windows,
                now: now,
              ),
            ),
        ],
      ),
    );
  }
}
