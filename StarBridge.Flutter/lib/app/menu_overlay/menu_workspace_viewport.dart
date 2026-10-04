import 'package:flutter/material.dart';

/// The painted workspace coordinates, shared only with native child surfaces.
/// This owns neither window placement nor business state.
class MenuWorkspaceViewport extends InheritedWidget {
  const MenuWorkspaceViewport({
    super.key,
    required this.size,
    required super.child,
  });

  final Size size;

  static Rect? logicalRect(BuildContext context, RenderBox child) {
    final parent = context
        .getElementForInheritedWidgetOfExactType<MenuWorkspaceViewport>()
        ?.renderObject;
    if (parent == null || !child.hasSize) return null;
    return MatrixUtils.transformRect(
      child.getTransformTo(parent),
      Offset.zero & child.size,
    );
  }

  static List<Rect> physicalRects(BuildContext context, Iterable<Rect> rects) {
    final element = context
        .getElementForInheritedWidgetOfExactType<MenuWorkspaceViewport>();
    final render = element?.renderObject;
    if (render is! RenderBox || !render.hasSize) return const [];
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return [
      for (final rect in rects)
        _physical(
          MatrixUtils.transformRect(render.getTransformTo(null), rect),
          ratio,
        ),
    ];
  }

  static Rect _physical(Rect rect, double ratio) => Rect.fromLTRB(
    rect.left * ratio,
    rect.top * ratio,
    rect.right * ratio,
    rect.bottom * ratio,
  );

  static Size? sizeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MenuWorkspaceViewport>()?.size;

  @override
  bool updateShouldNotify(MenuWorkspaceViewport oldWidget) =>
      size != oldWidget.size;
}
