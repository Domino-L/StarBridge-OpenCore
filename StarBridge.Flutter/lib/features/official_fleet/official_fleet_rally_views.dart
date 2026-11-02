import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/host/desktop_notification_port.dart';
import 'official_fleet_rally.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

String _count(AppStrings strings, String key, int count) =>
    strings.text(key).replaceAll('{count}', '$count');

String _failure(AppStrings strings, String code) => strings.text(
  'officialFleet.rally.failed.${const {'conflict', 'rateLimited', 'notAllowed'}.contains(code) ? code : 'unavailable'}',
);

/// Owner-only header action. Hidden while a rally runs (the strip owns it).
class OfficialFleetRallyStartButton extends StatelessWidget {
  const OfficialFleetRallyStartButton({required this.controller, super.key});
  final OfficialFleetRallyController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final running = controller.current?.activeAt(controller.now()) == true;
      if (!controller.canStart || running) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: StarBridgeActionButton(
          kind: StarBridgeActionKind.primary,
          controlKey: const Key('official-fleet-rally-start'),
          onActivate: controller.busy
              ? null
              : (source) => showStarBridgeDialog<void>(
                  context,
                  useRootNavigator: false,
                  source: source,
                  builder: (_) =>
                      OfficialFleetRallyDialog(controller: controller),
                ),
          child: Text(AppStrings.of(context).text('officialFleet.rally.start')),
        ),
      );
    },
  );
}

class OfficialFleetRallyDialog extends StatefulWidget {
  const OfficialFleetRallyDialog({required this.controller, super.key});
  final OfficialFleetRallyController controller;

  @override
  State<OfficialFleetRallyDialog> createState() =>
      _OfficialFleetRallyDialogState();
}

class _OfficialFleetRallyDialogState extends State<OfficialFleetRallyDialog> {
  static const _presets = ['gather', 'voice', 'support', 'online'];
  final _text = TextEditingController();
  int _minutes = 30;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(InteractionSource source) async {
    final failure = await widget.controller.start(_text.text, _minutes);
    if (!mounted) return;
    if (failure == null) {
      dismissStarBridgeDialog(context, source: source);
    } else {
      setState(() => _error = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context), tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final rights = widget.controller.eligibility;
    final length = _text.text.trim().characters.length;
    final valid = length > 0 && length <= 40 && rights.remainingThisHour > 0;
    Widget label(String key) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        strings.text(key),
        style: text.labelMedium?.copyWith(color: tokens.colors.textSecondary),
      ),
    );
    Widget choice(String label, bool selected, VoidCallback onTap, Key key) =>
        StarBridgeActionButton(
          controlKey: key,
          kind: selected
              ? StarBridgeActionKind.primary
              : StarBridgeActionKind.secondary,
          onActivate: (_) => onTap(),
          child: Text(label),
        );
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => AlertDialog(
        key: const Key('official-fleet-rally-dialog'),
        title: Text(strings.text('officialFleet.rally.start')),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('officialFleet.rally.hint'),
                style: text.bodySmall?.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
              label('officialFleet.rally.text'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _presets)
                    choice(
                      strings.text('officialFleet.rally.preset.$preset'),
                      _text.text ==
                          strings.text('officialFleet.rally.preset.$preset'),
                      () => _text.text = strings.text(
                        'officialFleet.rally.preset.$preset',
                      ),
                      Key('official-fleet-rally-preset-$preset'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('official-fleet-rally-text'),
                controller: _text,
                maxLength: 40,
                maxLines: 1,
              ),
              label('officialFleet.rally.target'),
              Text(
                _count(
                  strings,
                  'officialFleet.rally.targetValue',
                  rights.onlineCount,
                ),
                key: const Key('official-fleet-rally-target'),
              ),
              label('officialFleet.rally.duration'),
              Wrap(
                spacing: 8,
                children: [
                  for (final minutes in const [15, 30, 60])
                    choice(
                      _count(strings, 'officialFleet.rally.minutes', minutes),
                      _minutes == minutes,
                      () => setState(() => _minutes = minutes),
                      Key('official-fleet-rally-minutes-$minutes'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _count(
                  strings,
                  'officialFleet.rally.rules',
                  rights.remainingThisHour,
                ),
                style: text.bodySmall?.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _failure(strings, _error!),
                  key: const Key('official-fleet-rally-error'),
                  style: text.bodySmall?.copyWith(color: tokens.colors.danger),
                ),
              ],
            ],
          ),
        ),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('official-fleet-rally-cancel'),
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source),
            child: Text(strings.text('officialFleet.rally.cancel')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: const Key('official-fleet-rally-send'),
            onActivate: !valid || widget.controller.busy ? null : _send,
            child: Text(strings.text('officialFleet.rally.send')),
          ),
        ],
      ),
    );
  }
}

/// The page strip: live counts for everyone, answer buttons for members, the
/// end button for the owner. Counts only, never names.
class OfficialFleetRallyStrip extends StatefulWidget {
  const OfficialFleetRallyStrip({required this.controller, super.key});
  final OfficialFleetRallyController controller;

  @override
  State<OfficialFleetRallyStrip> createState() =>
      _OfficialFleetRallyStripState();
}

class _OfficialFleetRallyStripState extends State<OfficialFleetRallyStrip> {
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    // Keeps "N minutes left" and expiry honest between reads.
    _minute = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  Future<void> _run(
    InteractionSource source,
    Future<String?> Function() action,
  ) async {
    final strings = AppStrings.of(context);
    final failure = await action();
    if (failure == null || !mounted) return;
    showStarBridgeSnackBar(
      context,
      starBridgeTimedSnackBar(content: Text(_failure(strings, failure))),
      source: source,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final rally = controller.current, now = controller.now();
      final owner = controller.canStart;
      if (rally == null || (!rally.activeAt(now) && !owner)) {
        return const SizedBox.shrink();
      }
      final strings = AppStrings.of(context), tokens = context.tokens;
      final text = Theme.of(context).textTheme;
      final live = rally.activeAt(now);
      Widget count(int value, String key) => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$value ',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: strings.text(key),
              style: text.bodySmall?.copyWith(
                color: tokens.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
      Widget answer(OfficialFleetRallyAnswer value, String key) =>
          StarBridgeActionButton(
            controlKey: Key('official-fleet-rally-answer-${value.name}'),
            kind: rally.answer == value
                ? StarBridgeActionKind.primary
                : StarBridgeActionKind.secondary,
            onActivate: controller.busy
                ? null
                : (source) => _run(source, () => controller.respond(value)),
            child: Text(strings.text(key)),
          );
      return Container(
        key: const Key('official-fleet-rally-strip'),
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: live ? tokens.colors.warningSoft : null,
          border: Border.all(
            color: live ? tokens.colors.warning : tokens.colors.textDisabled,
          ),
        ),
        child: Wrap(
          spacing: 18,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              strings.text(
                live
                    ? 'officialFleet.rally.live'
                    : 'officialFleet.rally.closed',
              ),
              style: text.labelLarge?.copyWith(
                color: live
                    ? tokens.colors.warning
                    : tokens.colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '「${rally.text}」',
              key: const Key('official-fleet-rally-text-shown'),
            ),
            count(rally.coming, 'officialFleet.rally.coming'),
            count(rally.cannot, 'officialFleet.rally.cannot'),
            count(rally.pending, 'officialFleet.rally.pending'),
            if (live)
              Text(
                _count(
                  strings,
                  'officialFleet.rally.left',
                  rally.minutesLeft(now),
                ),
                style: text.bodySmall?.copyWith(
                  color: tokens.colors.textSecondary,
                ),
              ),
            if (live && owner)
              StarBridgeActionButton(
                controlKey: const Key('official-fleet-rally-end'),
                onActivate: controller.busy
                    ? null
                    : (source) => _run(source, controller.end),
                child: Text(strings.text('officialFleet.rally.end')),
              ),
            if (live && !owner) ...[
              answer(
                OfficialFleetRallyAnswer.coming,
                'officialFleet.rally.coming',
              ),
              answer(
                OfficialFleetRallyAnswer.cannot,
                'officialFleet.rally.cannot',
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// The shell notice for members on any page, plus one desktop notification
/// per rally (the Host decides whether it may show, e.g. not over a game).
class OfficialFleetRallyNotice extends StatefulWidget {
  const OfficialFleetRallyNotice({
    required this.controller,
    this.desktop,
    this.alertsEnabled,
    this.alertsChanged,
    super.key,
  });
  final OfficialFleetRallyController controller;
  final DesktopNotificationPort? desktop;
  // The rally alerts switch: off consumes the announcement without showing it;
  // null (settings not known yet) waits for [alertsChanged] and asks again.
  final bool? Function()? alertsEnabled;
  final Listenable? alertsChanged;

  @override
  State<OfficialFleetRallyNotice> createState() =>
      _OfficialFleetRallyNoticeState();
}

class _OfficialFleetRallyNoticeState extends State<OfficialFleetRallyNotice> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_announce);
    widget.alertsChanged?.addListener(_announce);
  }

  @override
  void didUpdateWidget(OfficialFleetRallyNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_announce);
      widget.controller.addListener(_announce);
    }
    if (!identical(oldWidget.alertsChanged, widget.alertsChanged)) {
      oldWidget.alertsChanged?.removeListener(_announce);
      widget.alertsChanged?.addListener(_announce);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_announce);
    widget.alertsChanged?.removeListener(_announce);
    super.dispose();
  }

  void _announce() {
    final desktop = widget.desktop;
    if (desktop == null || !mounted) return;
    final enabled = widget.alertsEnabled == null
        ? true
        : widget.alertsEnabled!();
    if (enabled == null) return;
    final rally = widget.controller.takeAnnouncement();
    if (rally == null || !enabled) return;
    final strings = AppStrings.of(context);
    unawaited(
      desktop.show(
        officialFleetRallyTitle(strings, widget.controller.fleetName, rally),
        '「${rally.text}」 · '
        '${_count(strings, 'officialFleet.rally.left', rally.minutesLeft(widget.controller.now()))}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final rally = controller.prompt;
      if (rally == null) return const SizedBox.shrink();
      final strings = AppStrings.of(context), tokens = context.tokens;
      final text = Theme.of(context).textTheme;
      return Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          key: const ValueKey('official-fleet-rally-notice'),
          color: tokens.colors.warningSoft,
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.lg,
            vertical: tokens.space.xs,
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                officialFleetRallyTitle(strings, controller.fleetName, rally),
                style: text.labelLarge?.copyWith(color: tokens.colors.warning),
              ),
              Text(
                '「${rally.text}」 · '
                '${_count(strings, 'officialFleet.rally.left', rally.minutesLeft(controller.now()))}',
                style: text.bodySmall,
              ),
              TextButton(
                key: const ValueKey('official-fleet-rally-notice-coming'),
                onPressed: controller.busy
                    ? null
                    : () => controller.respond(OfficialFleetRallyAnswer.coming),
                child: Text(strings.text('officialFleet.rally.coming')),
              ),
              TextButton(
                key: const ValueKey('official-fleet-rally-notice-cannot'),
                onPressed: controller.busy
                    ? null
                    : () => controller.respond(OfficialFleetRallyAnswer.cannot),
                child: Text(strings.text('officialFleet.rally.cannot')),
              ),
              TextButton(
                key: const ValueKey('official-fleet-rally-notice-later'),
                onPressed: controller.dismiss,
                child: Text(strings.text('officialFleet.rally.later')),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// "DMNPZ 召集", or with the starter when several leaders may rally:
/// "DMNPZ · Leader A 召集".
String officialFleetRallyTitle(
  AppStrings strings,
  String? fleet,
  OfficialFleetRally rally,
) {
  final name = rally.starterName;
  return (name == null
          ? strings.text('officialFleet.rally.title')
          : strings
                .text('officialFleet.rally.titleBy')
                .replaceAll('{name}', name))
      .replaceAll('{fleet}', fleet ?? '');
}
