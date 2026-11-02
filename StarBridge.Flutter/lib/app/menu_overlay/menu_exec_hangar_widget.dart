import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../features/tools/exec_hangar_overview.dart';
import '../../platform/window/menu_desktop_widgets.dart';
import '../../platform/window/menu_exec_hangar_summary.dart';
import 'menu_bridge_style.dart';
import 'menu_chrome_hint.dart';

/// Read-only menu rail item. Placement belongs to the clock/header, not the tool.
final class MenuExecHangarWidget extends StatefulWidget {
  const MenuExecHangarWidget({
    super.key,
    required this.port,
    required this.preferences,
    required this.editing,
    required this.onOpen,
    required this.onEdit,
    required this.onChanged,
    this.initial,
    this.onSnapshot,
  });
  final MenuExecHangarSummaryPort port;
  final MenuDesktopWidgets preferences;
  final bool editing;
  final VoidCallback onOpen, onEdit;
  final void Function(MenuDesktopWidgets, bool persist) onChanged;
  final MenuExecHangarSummary? initial;
  final ValueChanged<MenuExecHangarSummary>? onSnapshot;
  @override
  State<MenuExecHangarWidget> createState() => _WidgetState();
}

class _WidgetState extends State<MenuExecHangarWidget> {
  MenuExecHangarSummary? _snapshot;
  final _clock = Stopwatch();
  Timer? _timer;
  bool _reading = false, _failed = false;
  int _lastRead = 0;
  String t(String key) => AppStrings.of(context).text('execHangar.$key');
  @override
  void initState() {
    super.initState();
    _snapshot = widget.initial;
    _clock.start();
    _read();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_clock.elapsed.inSeconds - _lastRead >= 60) {
        _lastRead = _clock.elapsed.inSeconds;
        _read();
      }
      setState(() {});
    });
  }

  Future<void> _read() async {
    if (_reading) return;
    _reading = true;
    try {
      final value = await widget.port.read();
      if (!mounted) return;
      widget.onSnapshot?.call(value);
      setState(() {
        _snapshot = value;
        _failed = false;
        _clock.reset();
        _lastRead = 0;
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _snapshot;
    final now = summary?.now.add(_clock.elapsed);
    final reliable =
        summary?.reliable == true &&
        summary?.fetchedAt != null &&
        now!.difference(summary!.fetchedAt!) <= const Duration(hours: 6);
    final phase = now == null
        ? null
        : summary!.phases
              .where((p) => !now.isBefore(p.start) && now.isBefore(p.end))
              .firstOrNull;
    final next = phase == null
        ? null
        : phase.open
        ? summary!.windows
              .where((w) => !now!.isBefore(w.open) && now.isBefore(w.close))
              .firstOrNull
              ?.close
        : summary!.windows.where((w) => w.open.isAfter(now!)).firstOrNull?.open;
    final valid = reliable && phase != null && next != null;
    final leaving = phase?.open == true && phase!.green == 0 && phase.red == 0;
    final colors = context.tokens.colors;
    final state = phase == null
        ? ''
        : t(
            leaving
                ? 'closingSoon'
                : phase.open
                ? 'open'
                : 'closed',
          );
    final target = valid
        ? '${execHangarTime(next)} ${t(phase.open ? 'closes' : 'opens')}'
        : '';
    final countdown = valid ? execHangarCountdown(next, now) : '';
    final unavailable = t(
      summary == null
          ? _reading && !_failed
                ? 'widgetTimeLoading'
                : 'widgetUnavailable'
          : summary.fetchedAt == null
          ? 'widgetUnavailable'
          : 'widgetStale',
    );
    final label = [
      t('widgetOpen'),
      if (valid) ...[
        state,
        '${phase.green} ${t('lampGreen')}, ${phase.red} ${t('lampRed')}',
        countdown,
        target,
      ] else
        unavailable,
      if (leaving) t('leaveNow'),
    ].join(' · ');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 268),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MenuChromeHint(
            message: valid ? '$state · $target' : unavailable,
            excludeFromSemantics: true,
            child: BridgeMenuAction(
              key: const Key('menu-hangar-widget'),
              label: label,
              padding: const EdgeInsets.symmetric(vertical: 6),
              onPressed: widget.onOpen,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          t('title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (valid) ...[
                        const SizedBox(width: 6),
                        for (var i = 0; i < 5; i++)
                          Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                            child: StandardIcon(
                              i < phase.green + phase.red
                                  ? StandardIconSemantic.circle
                                  : StandardIconSemantic.circleOutline,
                              size: 10,
                              color: i < phase.green
                                  ? colors.success
                                  : i < phase.green + phase.red
                                  ? colors.danger
                                  : colors.textDisabled,
                            ),
                          ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (valid)
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          leaving
                              ? t('leaveNow')
                              : '$state · ${t(phase.open ? 'nextClose' : 'nextOpen')}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: leaving
                                    ? colors.danger
                                    : colors.textSecondary,
                              ),
                        ),
                        Text(
                          countdown,
                          key: const Key('menu-hangar-countdown'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontSize: 20,
                                color: leaving
                                    ? colors.danger
                                    : colors.textPrimary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    )
                  else
                    Text(
                      unavailable,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (_failed && summary != null)
                    Text(
                      t('offline'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          if (widget.editing)
            StarBridgeIconAction(
              controlKey: const Key('menu-hangar-remove'),
              label: t('widgetRemove'),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: const EdgeInsets.all(4),
              onActivate: (_) => widget.onChanged(
                widget.preferences.copyWith(hangar: false),
                true,
              ),
              icon: const StarBridgeIcon(
                StarBridgeIconSemantic.remove,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}
