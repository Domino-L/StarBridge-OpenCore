import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// QualityPass ⑥ (user 2026-10-29): a single line cut by the end fade shows its
/// full text when the pointer rests on it.
///
/// One instance sits at the root of a window instead of wrapping each label:
/// when the mouse rests, it hit-tests the pointer position and looks for a
/// paragraph set to [TextOverflow.fade] that really is cut. Text that fits and
/// multi-line ellipsis body text show nothing. Screen readers already get the
/// full string from the paragraph, so the tip is excluded from semantics, and
/// it appears without animation.
class FadedNameTip extends StatefulWidget {
  const FadedNameTip({required this.child, super.key});

  final Widget child;

  @override
  State<FadedNameTip> createState() => _FadedNameTipState();
}

class _FadedNameTipState extends State<FadedNameTip> {
  static const _fallbackDelay = Duration(milliseconds: 500);
  static const _maxVisible = Duration(seconds: 8);

  Timer? _restTimer;
  Timer? _visibleTimer;
  Offset? _pointer;
  String? _message;
  Rect? _anchor;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _restTimer?.cancel();
    _visibleTimer?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _hide();
    return false;
  }

  void _onHover(PointerHoverEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    _pointer = event.position;
    final anchor = _anchor;
    if (anchor != null && anchor.contains(event.position)) return;
    _hide();
    _restTimer = Timer(
      Theme.of(context).tooltipTheme.waitDuration ?? _fallbackDelay,
      _inspect,
    );
  }

  void _inspect() {
    final pointer = _pointer;
    if (!mounted || pointer == null) return;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      pointer,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderParagraph) continue;
      if (target.overflow != TextOverflow.fade || target.softWrap) return;
      if (!target.attached || !target.hasSize) return;
      if (target.getMaxIntrinsicWidth(double.infinity) <=
          target.size.width + 0.5) {
        return;
      }
      final message = target.text
          .toPlainText(includeSemanticsLabels: false)
          .replaceAll('￼', '')
          .trim();
      if (message.isEmpty) return;
      setState(() {
        _message = message;
        _anchor = MatrixUtils.transformRect(
          target.getTransformTo(null),
          Offset.zero & target.size,
        );
      });
      _visibleTimer = Timer(_maxVisible, _hide);
      return;
    }
  }

  void _hide() {
    _restTimer?.cancel();
    _visibleTimer?.cancel();
    if (_message == null || !mounted) return;
    setState(() {
      _message = null;
      _anchor = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    final anchor = _anchor;
    return MouseRegion(
      opaque: false,
      onExit: (_) => _hide(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: _onHover,
        onPointerDown: (_) => _hide(),
        onPointerSignal: (_) => _hide(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (message != null && anchor != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: CustomSingleChildLayout(
                      delegate: _TipLayout(anchor),
                      child: _Tip(message),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final tooltip = Theme.of(context).tooltipTheme;
    return Material(
      key: const Key('faded-name-tip'),
      type: MaterialType.transparency,
      child: Container(
        padding: tooltip.padding,
        decoration: tooltip.decoration,
        child: Text(message, style: tooltip.textStyle),
      ),
    );
  }
}

class _TipLayout extends SingleChildLayoutDelegate {
  const _TipLayout(this.anchor);

  static const _gap = 6.0;
  static const _margin = 8.0;
  static const _maxWidth = 420.0;

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = constraints.maxWidth - _margin * 2;
    return BoxConstraints(
      maxWidth: room < _maxWidth ? room.clamp(0.0, _maxWidth) : _maxWidth,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = size.width - childSize.width - _margin;
    final left = anchor.left.clamp(_margin, maxLeft < _margin ? _margin : maxLeft);
    final below = anchor.bottom + _gap;
    final top = below + childSize.height + _margin <= size.height
        ? below
        : anchor.top - _gap - childSize.height;
    return Offset(left, top < _margin ? _margin : top);
  }

  @override
  bool shouldRelayout(_TipLayout oldDelegate) => oldDelegate.anchor != anchor;
}
