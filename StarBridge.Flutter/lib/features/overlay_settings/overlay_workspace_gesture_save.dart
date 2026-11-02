import 'package:flutter/widgets.dart';

import 'overlay_workspace_module.dart';

/// Holds direct save while a pointer is down inside [child], so dragging a
/// slider or a module writes once when the gesture ends instead of on every
/// frame. Taps still save at once: the lift schedules a write on the next
/// microtask, and the tap's own edit lands in that same pointer event.
class OverlayWorkspaceGestureSave extends StatefulWidget {
  const OverlayWorkspaceGestureSave({
    required this.module,
    required this.child,
    super.key,
  });

  final OverlayWorkspaceModule module;
  final Widget child;

  @override
  State<OverlayWorkspaceGestureSave> createState() =>
      _OverlayWorkspaceGestureSaveState();
}

class _OverlayWorkspaceGestureSaveState
    extends State<OverlayWorkspaceGestureSave> {
  final _pointers = <int>{};

  void _down(PointerDownEvent event) {
    if (_pointers.add(event.pointer) && _pointers.length == 1) {
      widget.module.holdCommits();
    }
  }

  void _up(PointerEvent event) {
    if (_pointers.remove(event.pointer) && _pointers.isEmpty) {
      widget.module.releaseCommits();
    }
  }

  @override
  void didUpdateWidget(OverlayWorkspaceGestureSave old) {
    super.didUpdateWidget(old);
    if (!identical(old.module, widget.module) && _pointers.isNotEmpty) {
      old.module.releaseCommits();
      widget.module.holdCommits();
    }
  }

  @override
  void dispose() {
    if (_pointers.isNotEmpty) widget.module.releaseCommits();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}
