import 'dart:async';

import 'package:flutter/widgets.dart';

/// Warm a small, account-scoped snapshot on deliberate navigation intent.
/// No startup fan-out, no page mounting, and no navigation dependency on I/O.
class NavigationPrefetch extends StatefulWidget {
  const NavigationPrefetch({required this.child, this.prepare, super.key});
  final Widget child;
  final Future<void> Function()? prepare;

  @override
  State<NavigationPrefetch> createState() => _NavigationPrefetchState();
}

class _NavigationPrefetchState extends State<NavigationPrefetch> {
  Timer? _timer;
  bool _hovered = false, _focused = false, _requested = false;

  void _update() {
    _timer?.cancel();
    if (!_hovered && !_focused) {
      _requested = false;
      return;
    }
    if (_requested || widget.prepare == null) return;
    _timer = Timer(const Duration(milliseconds: 350), () async {
      _requested = true;
      try {
        await widget.prepare?.call();
      } catch (_) {
        // Optional warming must never surface an unhandled error or navigate.
        // The feature owns normal error/retry UI when actually opened.
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      _hovered = true;
      _update();
    },
    onExit: (_) {
      _hovered = false;
      _update();
    },
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) {
        _focused = value;
        _update();
      },
      child: widget.child,
    ),
  );
}
