import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import 'menu_hud_placement_bars.dart';
import 'menu_hud_placement_paint.dart';

/// One module in arrange mode: its outline, its name, optional sample content
/// and the resize corner (moved out of menu_hud_placement.dart for the
/// 800-line size gate). On the visor a side block leans as the visor draws it
/// ([transform], 11-11 user: "要用同样的3d效果"), so the outline lies over the
/// real visor block and a click lands where the block shows; drags report the
/// pointer's movement on screen, so the block follows the pointer whatever the
/// lean.
class MenuHudPlacementModule extends StatefulWidget {
  const MenuHudPlacementModule({
    super.key,
    required this.moduleKey,
    required this.rect,
    required this.selected,
    required this.dragging,
    required this.hovered,
    required this.locked,
    required this.resizable,
    required this.tag,
    required this.resizeLabel,
    required this.onHover,
    required this.onSelect,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    this.transform,
    this.content,
  });

  final String moduleKey, tag, resizeLabel;
  final Rect rect;
  final bool selected, dragging, hovered, locked, resizable;
  final Matrix4? transform;
  final Widget? content;
  final ValueChanged<bool> onHover;
  final VoidCallback onSelect, onEnd;

  /// [pointer]: where the gesture starts on screen (global).
  final void Function(bool resize, Offset pointer) onStart;

  /// [delta] is the pointer's movement on screen since the last update.
  final void Function(Offset delta, Offset pointer, bool resize) onMove;

  @override
  State<MenuHudPlacementModule> createState() => _MenuHudPlacementModuleState();
}

class _MenuHudPlacementModuleState extends State<MenuHudPlacementModule> {
  Offset? _last, _first;

  /// The pointer was cancelled: a started drag then ends through onPanEnd,
  /// which only this raw event (seen before the recognizer) tells apart.
  bool _cancelled = false;

  void _start(Offset global, bool resize) {
    _last = _first = global;
    _cancelled = false;
    widget.onStart(resize, global);
  }

  // A cancelled rally drag changes nothing: it goes back to where it was
  // grabbed before it ends, so it docks where it was (it is only saved on
  // release; review CX-OVERLAY-M102-R1 P2-5). Other blocks end as before.
  void _cancel() {
    final first = _first;
    if (widget.moduleKey == 'Notice' && first != null) _move(first, false);
    _end();
  }

  void _panEnd() {
    if (_cancelled) {
      _cancelled = false;
      _cancel();
    } else {
      _end();
    }
  }

  void _move(Offset global, bool resize) {
    final last = _last ?? global;
    _last = global;
    widget.onMove(global - last, global, resize);
  }

  void _end() {
    _last = _first = null;
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.moduleKey;
    Widget body = MouseRegion(
      onEnter: (_) => widget.onHover(true),
      onExit: (_) => widget.onHover(false),
      cursor: key == 'Crosshair' || widget.locked
          ? SystemMouseCursors.basic
          : SystemMouseCursors.move,
      child: Listener(
        onPointerCancel: (_) => _cancelled = true,
        child: GestureDetector(
          key: ValueKey('menu-hud-place-module-$key'),
          behavior: HitTestBehavior.opaque,
          // from where it was pressed: the point pressed stays under the pointer
          // (the slop it takes to start is caught up on the first move)
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: (_) => widget.onSelect(),
          onPanStart: (details) => _start(details.globalPosition, false),
          onPanUpdate: (details) => _move(details.globalPosition, false),
          onPanEnd: (_) => _panEnd(),
          onPanCancel: _cancel,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.content case final content?)
                Positioned.fill(child: IgnorePointer(child: content)),
              Positioned.fill(
                child: CustomPaint(
                  painter: MenuHudModuleOutline(
                    selected: widget.selected,
                    dragging: widget.dragging,
                    hovered: widget.hovered,
                  ),
                ),
              ),
              // the module's name is always shown (11-11 "一直显示模块名")
              MenuHudModuleTag(below: widget.rect.top < 30, text: widget.tag),
              if (widget.resizable)
                MenuHudResizeGrip(
                  moduleKey: key,
                  label: widget.resizeLabel,
                  onStart: (global) => _start(global, true),
                  onUpdate: (details) => _move(details.globalPosition, true),
                  onEnd: _end,
                ),
            ],
          ),
        ),
      ),
    );
    if (widget.transform case final transform?) {
      body = Transform(transform: transform, child: body);
    }
    return Positioned.fromRect(rect: widget.rect, child: body);
  }
}
