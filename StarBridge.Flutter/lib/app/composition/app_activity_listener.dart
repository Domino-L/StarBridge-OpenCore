import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_activity_presence.dart';

/// Observe all Flutter routes (including menus/dialogs) without consuming input.
class AppActivityListener extends StatefulWidget {
  const AppActivityListener({
    required this.activity,
    required this.child,
    super.key,
  });

  final AppActivityPresence activity;
  final Widget child;

  @override
  State<AppActivityListener> createState() => _AppActivityListenerState();
}

class _AppActivityListenerState extends State<AppActivityListener> {
  @override
  void initState() {
    super.initState();
    widget.activity.start();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    HardwareKeyboard.instance.addHandler(_key);
  }

  void _pointer(PointerEvent event) {
    if (!event.synthesized &&
        (event is PointerDownEvent ||
            event is PointerMoveEvent ||
            event is PointerHoverEvent ||
            event is PointerSignalEvent ||
            event is PointerPanZoomUpdateEvent)) {
      widget.activity.recordInteraction();
    }
  }

  bool _key(KeyEvent event) {
    if (!event.synthesized) widget.activity.recordInteraction();
    return false;
  }

  @override
  void didUpdateWidget(AppActivityListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity != widget.activity) {
      oldWidget.activity.stop();
      widget.activity.start();
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    HardwareKeyboard.instance.removeHandler(_key);
    widget.activity.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
