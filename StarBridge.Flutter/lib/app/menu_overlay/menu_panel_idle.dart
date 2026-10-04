import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/window/native_viewport_visibility.dart';

/// A bounded idle delay, never a polling loop. Native children share the same
/// opacity target and report interaction through their existing status lane.
class MenuPanelIdle extends StatefulWidget {
  const MenuPanelIdle({super.key, required this.shown, required this.child});
  final bool shown;
  final Widget child;
  @override
  State<MenuPanelIdle> createState() => _MenuPanelIdleState();
}

class _MenuPanelIdleState extends State<MenuPanelIdle>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _fade;
  bool _reduceMotion = false;
  bool _hovered = false,
      _pressed = false,
      _nativeActive = false,
      _dimmed = false;
  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, lowerBound: .7, value: 1);
    nativeViewportMenus.addListener(_refresh);
    FocusManager.instance.addListener(_refresh);
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _fade.value = _dimmed ? .7 : 1;
  }

  bool get _editing {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null ||
        focused.findAncestorWidgetOfExactType<EditableText>() == null) {
      return false;
    }
    return focused.findAncestorStateOfType<_MenuPanelIdleState>() == this;
  }

  void _refresh() {
    if (!mounted) return;
    final active =
        !widget.shown ||
        _hovered ||
        _pressed ||
        _nativeActive ||
        _editing ||
        nativeViewportMenus.value > 0;
    if (active) {
      _timer?.cancel();
      _timer = null;
      if (_dimmed) {
        _dimmed = false;
        _fade.value = 1; // Interaction interrupts the fade, without a queue.
      }
    } else if (!_dimmed) {
      _timer ??= Timer(const Duration(seconds: 5), () {
        _timer = null;
        if (!mounted) return;
        _dimmed = true;
        if (_reduceMotion) {
          _fade.value = .7;
        } else {
          _fade.animateTo(
            .7,
            duration: const Duration(milliseconds: 220),
            curve: const Cubic(.22, 1, .36, 1),
          );
        }
      });
    }
  }

  void _nativeInteraction(bool active) {
    if (_nativeActive == active) return;
    _nativeActive = active;
    _refresh();
  }

  @override
  void didUpdateWidget(covariant MenuPanelIdle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.shown) {
      _hovered = false;
      _pressed = false;
      _nativeActive = false;
    }
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    nativeViewportMenus.removeListener(_refresh);
    FocusManager.instance.removeListener(_refresh);
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    // Stop at a painted child; deferToChild still lets pure-image transparent
    // chrome pass through. opaque:false also hits obscured sibling windows.
    opaque: true,
    hitTestBehavior: HitTestBehavior.deferToChild,
    onEnter: (_) {
      _hovered = true;
      _refresh();
    },
    onExit: (_) {
      _hovered = false;
      _refresh();
    },
    child: Listener(
      onPointerDown: (_) {
        _pressed = true;
        _refresh();
      },
      onPointerUp: (_) {
        _pressed = false;
        _refresh();
      },
      onPointerCancel: (_) {
        _pressed = false;
        _refresh();
      },
      child: AnimatedBuilder(
        animation: _fade,
        child: widget.child,
        builder: (context, child) => MenuPanelIdleScope(
          // The native browser consumes this same intermediate opacity via
          // its existing bounds update. No separate animation timer or poll.
          opacity: _fade.value,
          nativeInteraction: _nativeInteraction,
          child: Opacity(
            key: const ValueKey('menu-panel-idle-opacity'),
            opacity: _fade.value,
            child: child,
          ),
        ),
      ),
    ),
  );
}

class MenuPanelIdleScope extends InheritedWidget {
  const MenuPanelIdleScope({
    super.key,
    required this.opacity,
    required this.nativeInteraction,
    required super.child,
  });
  final double opacity;
  final ValueChanged<bool> nativeInteraction;
  static MenuPanelIdleScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MenuPanelIdleScope>();
  @override
  bool updateShouldNotify(MenuPanelIdleScope oldWidget) =>
      oldWidget.opacity != opacity;
}
