import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/tokens/starbridge_tokens.dart';

/// Shows [detail] beside [child] while the pointer rests on either of them or
/// focus is inside [child] (0.7.2 sidebar option C). The card stays open while
/// the pointer moves onto it, so its rows can be clicked; Escape closes it.
class AttentionDetailHover extends StatefulWidget {
  const AttentionDetailHover({
    required this.detail,
    required this.child,
    this.enabled = true,
    super.key,
  });
  final WidgetBuilder detail;
  final Widget child;
  final bool enabled;
  @override
  State<AttentionDetailHover> createState() => _AttentionDetailHoverState();
}

class _AttentionDetailHoverState extends State<AttentionDetailHover> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  bool _anchor = false, _card = false, _focus = false;
  Timer? _timer;

  void _update() {
    _timer?.cancel();
    final want = widget.enabled && (_anchor || _card || _focus);
    if (want == _portal.isShowing) return;
    // Open after a short rest (like tooltips); close a moment later so the
    // pointer can cross the gap onto the card.
    _timer = Timer(Duration(milliseconds: want ? (_focus ? 0 : 300) : 150), () {
      if (!mounted) return;
      final still = widget.enabled && (_anchor || _card || _focus);
      if (still && !_portal.isShowing) _portal.show();
      if (!still && _portal.isShowing) _portal.hide();
    });
  }

  @override
  void didUpdateWidget(AttentionDetailHover old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && _portal.isShowing) _portal.hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(6, 0),
          child: Align(
            alignment: Alignment.topLeft,
            child: MouseRegion(
              onEnter: (_) => setState(() {
                _card = true;
                _update();
              }),
              onExit: (_) => setState(() {
                _card = false;
                _update();
              }),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      _portal.hide,
                },
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    key: const Key('attention-detail-card'),
                    width: 250,
                    decoration: BoxDecoration(
                      color: t.surfaces.panel.fill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.surfaces.panel.border),
                    ),
                    child: widget.detail(context),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) {
            _anchor = true;
            _update();
          },
          onExit: (_) {
            _anchor = false;
            _update();
          },
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (focused) {
              _focus = focused;
              _update();
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
