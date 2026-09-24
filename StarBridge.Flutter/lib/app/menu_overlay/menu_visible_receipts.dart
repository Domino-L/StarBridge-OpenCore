import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Only the foreground tool's actually painted incoming message may be read.
class MenuVisibleReceipts extends StatefulWidget {
  const MenuVisibleReceipts({
    super.key,
    required this.active,
    required this.tokens,
    required this.onRead,
    required this.builder,
  });
  final bool active;
  final Map<int, String> tokens;
  final ValueChanged<String> onRead;
  final Widget Function(Map<int, GlobalKey>) builder;
  @override
  State<MenuVisibleReceipts> createState() => _MenuVisibleReceiptsState();
}

class _MenuVisibleReceiptsState extends State<MenuVisibleReceipts> {
  final _anchors = <int, GlobalKey>{};
  ScrollPosition? _position;
  bool _scheduled = false;
  String? _attempted;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (_position != next) {
      _position?.removeListener(_schedule);
      _position = next;
      _position?.addListener(_schedule);
    }
    _schedule();
  }

  void _schedule() {
    if (_scheduled || !widget.active) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !widget.active || !TickerMode.valuesOf(context).enabled) {
        return;
      }
      String? visible;
      for (final entry in widget.tokens.entries) {
        final box = _anchors[entry.key]?.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) continue;
        final rawViewport = RenderAbstractViewport.maybeOf(box);
        if (rawViewport is! RenderBox) continue;
        final viewport = rawViewport as RenderBox;
        if (!viewport.hasSize) continue;
        final bounds = box.localToGlobal(Offset.zero) & box.size;
        var clip = viewport.localToGlobal(Offset.zero) & viewport.size;
        // Tiny tool windows scroll around the inner history viewport. A message
        // visible to that inner list may still be clipped by the outer window.
        RenderObject? ancestor = viewport.parent;
        while (ancestor != null) {
          if (ancestor is RenderAbstractViewport && ancestor is RenderBox) {
            final outer = ancestor as RenderBox;
            if (!outer.hasSize) break;
            clip = clip.intersect(
              outer.localToGlobal(Offset.zero) & outer.size,
            );
          }
          ancestor = ancestor.parent;
        }
        if (bounds.overlaps(clip) && bounds.intersect(clip).height >= 16) {
          visible = entry.value;
        }
      }
      if (visible != null && visible != _attempted) {
        _attempted = visible;
        widget.onRead(visible);
      }
    });
  }

  @override
  void didUpdateWidget(MenuVisibleReceipts oldWidget) {
    super.didUpdateWidget(oldWidget);
    _anchors.removeWhere((index, _) => !widget.tokens.containsKey(index));
    _schedule();
  }

  @override
  void dispose() {
    _position?.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final index in widget.tokens.keys) {
      _anchors.putIfAbsent(index, GlobalKey.new);
    }
    _schedule();
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _schedule();
        return false;
      },
      child: widget.builder(_anchors),
    );
  }
}
