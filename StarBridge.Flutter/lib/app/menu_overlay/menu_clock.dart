import 'dart:async';

import 'package:flutter/material.dart';

import 'menu_bridge_style.dart';
import '../../platform/window/menu_display_preferences.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../presence/manual_presence_widgets.dart';
import '../shell/chrome/presence_color.dart';

String menuClockText(
  BuildContext context,
  DateTime now,
  String format, {
  bool? system24Hour,
}) {
  if (format == 'system' && system24Hour != null) {
    format = system24Hour ? 'twentyFourHour' : 'twelveHour';
  }
  final local = MaterialLocalizations.of(context);
  if (format == 'system') {
    return local.formatTimeOfDay(
      TimeOfDay.fromDateTime(now),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
  String two(int n) => n.toString().padLeft(2, '0');
  if (format == 'twentyFourHour') return '${two(now.hour)}:${two(now.minute)}';
  final time = '${now.hour % 12 == 0 ? 12 : now.hour % 12}:${two(now.minute)}';
  final period = now.hour < 12
      ? local.anteMeridiemAbbreviation
      : local.postMeridiemAbbreviation;
  return Localizations.localeOf(context).languageCode == 'zh'
      ? '$period $time'
      : '$time $period';
}

class MenuClock extends StatefulWidget {
  const MenuClock({
    super.key,
    this.preferences = const MenuDisplayPreferences(),
    this.presenceKey = 'presence.unknown',
    this.system24Hour,
  });
  final MenuDisplayPreferences preferences;
  final String presenceKey;
  final bool? system24Hour;
  @override
  State<MenuClock> createState() => _MenuClockState();
}

class _MenuClockState extends State<MenuClock> {
  late DateTime now = DateTime.now();
  late final Timer timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final updated = DateTime.now();
      if (updated.year != now.year ||
          updated.month != now.month ||
          updated.day != now.day ||
          updated.hour != now.hour ||
          updated.minute != now.minute ||
          updated.timeZoneOffset != now.timeZoneOffset) {
        setState(() => now = updated);
      }
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 20, 8),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: BridgeInk.blue, width: 1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.preferences.showClock)
          Text(
            menuClockText(
              context,
              now,
              widget.preferences.clockFormat,
              system24Hour: widget.system24Hour,
            ),
            key: const ValueKey('menu-local-clock'),
            style: const TextStyle(
              fontSize: 44,
              height: 1.1,
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w300,
              letterSpacing: 1.5,
            ),
          ),
        if (widget.preferences.showDate) ...[
          const SizedBox(height: 5),
          BridgeCaption(
            MaterialLocalizations.of(context).formatFullDate(now),
            key: const ValueKey('menu-local-date'),
          ),
        ],
        if (widget.preferences.showPresence) ...[
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                key: const ValueKey('menu-local-presence-dot'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: presenceColor(
                    context.tokens.colors,
                    widget.presenceKey == 'presence.invisible'
                        ? 'presence.offline'
                        : widget.presenceKey,
                  ),
                ),
                child: const SizedBox.square(dimension: 7),
              ),
              const SizedBox(width: 7),
              Text(
                manualPresenceText(context, widget.presenceKey),
                key: const ValueKey('menu-local-presence'),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
