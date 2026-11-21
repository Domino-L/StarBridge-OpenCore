import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/tokens/starbridge_tokens.dart';

/// Shows [detail] beside [child] while the pointer rests on either of them or
/// focus is inside [child] (0.7.2 sidebar option C). The card stays open while
/// the pointer moves onto it, so its rows can be clicked.
///
/// It closes when the pointer leaves both, on a click outside both, on Escape
/// and when focus leaves [child]. A click on [child] also focuses it, so focus
/// alone must not hold the card after the pointer has gone; once closed this
/// way it opens again only on a new hover or a new focus.
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
  bool _anchor = false, _card = false, _focus = false, _dismissed = false;
  Timer? _timer;

  bool get _want =>
      widget.enabled && !_dismissed && (_anchor || _card || _focus);

  void _update({bool leaving = false}) {
    _timer?.cancel();
    if (!leaving && _want == _portal.isShowing) return;
    // Open after a short rest (like tooltips); close a moment later so the
    // pointer can cross the gap onto the card.
    final open = _want && !leaving;
    _timer = Timer(Duration(milliseconds: open ? (_focus ? 0 : 300) : 150), () {
      if (!mounted) return;
      if (leaving && !_anchor && !_card) _dismissed = true;
      if (_want && !_portal.isShowing) _portal.show();
      if (!_want && _portal.isShowing) _portal.hide();
    });
  }

  void _enter(void Function() mark) {
    _dismissed = false;
    mark();
    _update();
  }

  void _dismiss() {
    _timer?.cancel();
    _dismissed = true;
    if (_portal.isShowing) _portal.hide();
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !_portal.isShowing) {
      return KeyEventResult.ignored;
    }
    _dismiss();
    return KeyEventResult.handled;
  }

  // Escape with focus elsewhere (the card opened on hover alone). Focus
  // handlers run first, so Escape inside [child] or the card is not seen twice.
  bool _escape(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !_portal.isShowing) {
      return false;
    }
    _dismiss();
    return true;
  }

  void _tapOutside(PointerDownEvent _) {
    if (_portal.isShowing || _timer?.isActive == true) _dismiss();
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_escape);
  }

  @override
  void didUpdateWidget(AttentionDetailHover old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && _portal.isShowing) _portal.hide();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_escape);
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
            child: TapRegion(
              groupId: this,
              onTapOutside: _tapOutside,
              child: MouseRegion(
                onEnter: (_) => _enter(() => _card = true),
                onExit: (_) {
                  _card = false;
                  _update(leaving: true);
                },
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _key,
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
        ),
        child: TapRegion(
          groupId: this,
          onTapOutside: _tapOutside,
          child: MouseRegion(
            onEnter: (_) => _enter(() => _anchor = true),
            onExit: (_) {
              _anchor = false;
              _update(leaving: true);
            },
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _key,
              onFocusChange: (focused) {
                if (focused) _dismissed = false;
                _focus = focused;
                _update();
              },
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
