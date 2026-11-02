import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

/// Keeps the native Dialog/AlertDialog tree and measures its outer Material
/// surface. Insets and alignment are layout, not the boundary of the artwork.
class StarBridgeDialogSurface extends StarBridgeMeasuredSurface {
  const StarBridgeDialogSurface({
    required super.animation,
    required super.child,
    super.key,
  }) : super(kind: SurfaceKind.dialog);
}

/// Shares the native Material measurement between dialog and queued toast.
/// Insets remain layout; only the actual physical surface receives artwork.
class StarBridgeMeasuredSurface extends StatefulWidget {
  const StarBridgeMeasuredSurface({
    required this.animation,
    required this.child,
    required this.kind,
    this.tone,
    super.key,
  });
  final Animation<double> animation;
  final Widget child;
  final SurfaceKind kind;
  final Color? tone;

  @override
  State<StarBridgeMeasuredSurface> createState() => _DialogSurfaceState();
}

class _DialogSurfaceState extends State<StarBridgeMeasuredSurface> {
  (Rect, Size) _geometry = (Rect.zero, Size.zero);

  void _measured(Rect rect, Size size) {
    final next = (rect, size);
    if (mounted && _geometry != next) setState(() => _geometry = next);
  }

  @override
  Widget build(BuildContext context) {
    final (rect, size) = _geometry;
    final origin = size.isEmpty
        ? Alignment.center
        : Alignment(
            rect.center.dx / size.width * 2 - 1,
            rect.center.dy / size.height * 2 - 1,
          );
    return SuiteSurfaceTransition(
      animation: widget.animation,
      kind: widget.kind,
      tone: widget.tone,
      alignment: widget.kind == SurfaceKind.toast
          ? Alignment.bottomCenter
          : Alignment.topLeft,
      surfaceBounds: rect,
      surfaceAlignment: origin,
      child: _SurfaceProbe(onGeometry: _measured, child: widget.child),
    );
  }
}

class _SurfaceProbe extends SingleChildRenderObjectWidget {
  const _SurfaceProbe({required this.onGeometry, required super.child});
  final void Function(Rect, Size) onGeometry;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSurfaceProbe(onGeometry);

  @override
  void updateRenderObject(BuildContext context, _RenderSurfaceProbe object) {
    object.onGeometry = onGeometry;
  }
}

class _RenderSurfaceProbe extends RenderProxyBox {
  _RenderSurfaceProbe(this.onGeometry);
  void Function(Rect, Size) onGeometry;
  bool _queued = false;

  // Both are public Flutter render types. The first physical surface is the
  // outer Dialog Material; nested buttons/cards cannot replace its boundary.
  RenderBox? _surface(RenderObject node) {
    if ((node is RenderPhysicalShape || node is RenderPhysicalModel) &&
        node is RenderBox &&
        node.hasSize &&
        node.attached) {
      return node;
    }
    RenderBox? result;
    node.visitChildren((child) => result ??= _surface(child));
    return result;
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_queued) return;
    _queued = true;
    // Descendant sizes/transforms may only be read after layout completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (attached && hasSize) _measure();
    });
  }

  void _measure() {
    final target = child == null ? null : _surface(child!);
    final bounds = target == null
        ? Offset.zero & size
        : MatrixUtils.transformRect(
            target.getTransformTo(this),
            Offset.zero & target.size,
          );
    if (bounds.isFinite) onGeometry(bounds, size);
  }
}
