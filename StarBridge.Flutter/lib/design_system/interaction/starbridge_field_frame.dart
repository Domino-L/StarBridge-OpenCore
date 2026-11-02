import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_interaction_theme.dart';

/// Paint/focus presentation only. The builder keeps the original native
/// control, controller, validation, selection/IME, submit and storage owner.
/// The hierarchy is identical across suites, so changing style cannot dispose
/// an editor. Helpers/errors/counters determine the intrinsic height as before.
class StarBridgeFieldFrame extends StatefulWidget {
  const StarBridgeFieldFrame({
    required this.builder,
    this.focusNode,
    this.error = false,
    this.followNativeError = false,
    this.enabled = true,
    this.cursor = SystemMouseCursors.text,
    super.key,
  });
  final Widget Function(BuildContext context, FocusNode focus) builder;
  final FocusNode? focusNode;
  final bool error, enabled;

  /// Opt in to the actual error currently displayed by the native decorator.
  /// No mirrored validation flag, second FormField, or scheduled repaint loop.
  final bool followNativeError;
  final MouseCursor cursor;
  @override
  State<StarBridgeFieldFrame> createState() => _StarBridgeFieldFrameState();
}

class _StarBridgeFieldFrameState extends State<StarBridgeFieldFrame> {
  final _ownedFocus = FocusNode(debugLabel: 'StarBridge-native-control');
  final _frame = GlobalKey(), _child = GlobalKey();
  Element? _editable;
  RenderObject? _editableRender;
  Element? _label;
  Object? _labelIdentity;
  Rect? _labelBounds() {
    if (_editable?.mounted != true) return null;
    final decoration = _editable!
        .findAncestorWidgetOfExactType<InputDecorator>()
        ?.decoration;
    final identity = decoration?.label ?? decoration?.labelText;
    if (identity == null) return null;
    if (_label?.mounted != true || _labelIdentity != identity) {
      _label = null;
      _labelIdentity = identity;
      void visit(Element element) {
        if (_label != null) return;
        final w = element.widget;
        if (identical(w, decoration?.label) ||
            (decoration?.labelText != null &&
                w is Text &&
                w.data == decoration?.labelText)) {
          _label = element;
          return;
        }
        element.visitChildElements(visit);
      }

      (_child.currentContext as Element?)?.visitChildElements(visit);
    }
    final box = _label?.findRenderObject(),
        frame = _frame.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        frame is! RenderBox ||
        !box.attached ||
        !box.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      box.getTransformTo(frame),
      Offset.zero & box.size,
    ).inflate(2);
  }

  Rect _bounds(Size size) {
    if (_editable?.mounted != true || _editableRender?.attached != true) {
      _editable = null;
      _editableRender = null;
      _label = null;
      _labelIdentity = null;
      void visit(Element element) {
        if (_editable != null) return;
        if (element.widget is EditableText) {
          _editable = element;
          _editableRender = element.findRenderObject();
          return;
        }
        element.visitChildElements(visit);
      }

      (_child.currentContext as Element?)?.visitChildElements(visit);
    }
    final container = _editable == null
        ? null
        : InputDecorator.containerOf(_editable!);
    final frame = _frame.currentContext?.findRenderObject();
    if (container != null &&
        container.attached &&
        container.hasSize &&
        frame is RenderBox &&
        frame.hasSize) {
      return container.localToGlobal(Offset.zero, ancestor: frame) &
          container.size;
    }
    return Offset.zero & size;
  }

  bool _nativeError() {
    // The painter resolves _bounds first. Keep only the existing element cache;
    // read the current decoration each time, including independent SDK rebuilds.
    if (_editable?.mounted != true || _editableRender?.attached != true) {
      return false;
    }
    final decoration = _editable!
        .findAncestorWidgetOfExactType<InputDecorator>()
        ?.decoration;
    return decoration?.error != null || decoration?.errorText != null;
  }

  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        // A caller may deliberately rekey its native editor (conversation or
        // draft revision). Mounted alone does not mean the old Element is
        // still active during this frame. Resolve the rebuilt child afresh;
        // subsequent animation paints still share the per-build cache.
        _editable = null;
        _editableRender = null;
        _label = null;
        _labelIdentity = null;
        final focus = widget.focusNode ?? _ownedFocus;
        return SuiteFieldFrame(
          key: _frame,
          focusNode: focus,
          height: null,
          foregroundOnly: true,
          enabled: widget.enabled,
          error: widget.error,
          errorResolver: widget.followNativeError ? _nativeError : null,
          cursor: widget.cursor,
          boundsResolver: _bounds,
          paintExclusionResolver: _labelBounds,
          child: KeyedSubtree(
            key: _child,
            child: widget.builder(context, focus),
          ),
        );
      },
    ),
  );
}
