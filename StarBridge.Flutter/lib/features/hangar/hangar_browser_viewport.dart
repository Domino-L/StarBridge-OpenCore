import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/window/native_viewport_visibility.dart';
import 'hangar_reader_port.dart';

class HangarBrowserViewport extends StatefulWidget {
  const HangarBrowserViewport({
    required this.browser,
    required this.visible,
    this.interactive = true,
    super.key,
  });
  final HangarBrowserPort browser;
  final bool visible;
  final bool interactive;
  @override
  State<HangarBrowserViewport> createState() => _HangarBrowserViewportState();
}

class _HangarBrowserViewportState extends State<HangarBrowserViewport>
    with WidgetsBindingObserver {
  Rect _last = Rect.zero;
  final FocusNode _focus = FocusNode();
  bool _shown = false, _active = true, _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    nativeViewportMenus.addListener(_sync);
    widget.browser.setFocusExitHandler((previous) {
      if (!mounted) return;
      if (previous) {
        _focus.previousFocus();
      } else {
        _focus.nextFocus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Focusing a native child can make Flutter inactive without hiding the app.
    _foreground =
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    nativeViewportMenus.removeListener(_sync);
    widget.browser.setFocusExitHandler(null);
    _focus.dispose();
    unawaited(
      widget.browser.bounds(_last, visible: false).catchError((Object _) {}),
    );
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final offset = render.localToGlobal(Offset.zero);
    final rect = Rect.fromLTWH(
      offset.dx * ratio,
      offset.dy * ratio,
      render.size.width * ratio,
      render.size.height * ratio,
    );
    final visible =
        widget.visible &&
        _active &&
        _foreground &&
        nativeViewportMenus.value == 0;
    if (_last == rect && _shown == visible) return;
    _last = rect;
    _shown = visible;
    unawaited(
      widget.browser.bounds(rect, visible: visible).catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    _active =
        NativeViewportScope.isActive(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
        return Focus(
          canRequestFocus: widget.interactive,
          focusNode: _focus,
          onFocusChange: (focused) {
            if (focused && widget.visible && widget.interactive) {
              unawaited(widget.browser.focus().catchError((Object _) {}));
            }
          },
          child: Semantics(label: 'RSI', child: const SizedBox.expand()),
        );
      },
    );
  }
}
