import 'dart:async';

import 'package:flutter/material.dart';

import 'menu_bridge_style.dart';

class MenuClock extends StatefulWidget {
  const MenuClock({super.key});
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
      if (updated.minute != now.minute ||
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

  String two(int n) => n.toString().padLeft(2, '0');
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 20, 8),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: BridgeInk.blue, width: 1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${two(now.hour)}:${two(now.minute)}',
          key: const ValueKey('menu-local-clock'),
          style: const TextStyle(
            fontSize: 44,
            height: 1.1,
            fontFeatures: [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w300,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 5),
        BridgeCaption(
          '${now.year}年${now.month}月${now.day}日  星期${'一二三四五六日'[now.weekday - 1]}',
        ),
      ],
    ),
  );
}
