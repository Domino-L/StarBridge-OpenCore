import 'package:flutter/material.dart';

/// Native child windows have an independent z-order. Hide them while a Flutter
/// menu is open, including during menu disposal or destination exit animation.
final nativeViewportMenus = ValueNotifier<int>(0);

class NativeViewportMenu extends StatefulWidget {
  const NativeViewportMenu({required this.builder, super.key});
  final Widget Function(VoidCallback onOpen, VoidCallback onClose) builder;
  @override
  State<NativeViewportMenu> createState() => _NativeViewportMenuState();
}

class _NativeViewportMenuState extends State<NativeViewportMenu> {
  bool _open = false;
  void _change(bool value) {
    if (_open == value) return;
    _open = value;
    nativeViewportMenus.value += value ? 1 : -1;
  }

  @override
  void dispose() {
    _change(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(() => _change(true), () => _change(false));
}

class NativeViewportScope extends InheritedWidget {
  const NativeViewportScope({
    required this.active,
    required super.child,
    super.key,
  });
  final bool active;
  static bool isActive(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NativeViewportScope>()
          ?.active ??
      true;
  @override
  bool updateShouldNotify(NativeViewportScope oldWidget) =>
      active != oldWidget.active;
}
