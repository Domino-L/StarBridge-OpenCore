import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'painters.dart';
import 'suite.dart';

/// Side drawer over the page (detail panels, filters). Place it in a
/// [Stack] that covers the page; it paints its own scrim.
///
/// Rail: slides in from the edge with a lit leading rail. Scan: a line forms
/// at the edge and opens into the panel. Glow: slides a short way and fades
/// in with a soft edge light. Standard: a plain slide. Closing is quicker.
/// Esc and scrim taps close; focus moves into the drawer when it opens and
/// back to the previous element when it closes. [instant] (keyboard) and
/// reduced motion open and close without animation; Esc always closes
/// instantly, even if the caller does not pass [instant].
///
/// While closing, the drawer keeps showing the [child] it had when it was
/// last open (so the caller may clear its selection right away) but no
/// longer takes taps, focus or semantics. Reopening uses the new child.
class SuiteDrawer extends StatefulWidget {
  const SuiteDrawer({
    required this.open,
    required this.onClose,
    required this.child,
    this.width = 320,
    this.instant = false,
    this.semanticLabel,
    super.key,
  });

  final bool open;
  final VoidCallback onClose;
  final Widget child;
  final double width;
  final bool instant;
  final String? semanticLabel;

  @override
  State<SuiteDrawer> createState() => _SuiteDrawerState();
}

class _SuiteDrawerState extends State<SuiteDrawer>
    with SingleTickerProviderStateMixin {
  late final _t = AnimationController(vsync: this, value: widget.open ? 1 : 0)
    ..addStatusListener((_) {
      if (mounted) setState(() {});
    });
  final _scope = FocusScopeNode(debugLabel: 'drawer');
  FocusNode? _returnTo;

  /// Keeps the panel mounted when its transition wrappers change.
  final _keep = GlobalKey(debugLabel: 'drawer-panel');

  /// The content shown while open, kept for the exit.
  Widget? _content;

  /// Esc was pressed: the close it triggers skips the exit.
  bool _escape = false;

  void _escapeClose() {
    _escape = true;
    widget.onClose();
    // The caller may ignore the request (kept open): forget it after this
    // frame so a later pointer close still animates.
    WidgetsBinding.instance.addPostFrameCallback((_) => _escape = false);
  }

  @override
  void didUpdateWidget(SuiteDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    final escape = _escape;
    _escape = false;
    final data = InteractionScope.of(context);
    if (widget.open) {
      _returnTo = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scope.requestFocus();
      });
    } else {
      final back = _returnTo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (back != null && back.context != null) back.requestFocus();
      });
    }
    if (!data.animates || widget.instant || (escape && !widget.open)) {
      _t.value = widget.open ? 1 : 0;
      if (_t.isDismissed) _content = null;
      return;
    }
    _t.duration = data.suite == InteractionSuite.scan
        ? const Duration(milliseconds: 340)
        : const Duration(milliseconds: 260);
    _t.reverseDuration = const Duration(milliseconds: 160);
    widget.open ? _t.forward() : _t.reverse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates && _t.isAnimating) {
      _t.value = _t.status == AnimationStatus.reverse ? 0 : 1;
      if (_t.isDismissed) _content = null;
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_t.isDismissed) {
      _content = null;
      return const SizedBox.shrink();
    }
    if (widget.open) _content = widget.child;
    final closing = !widget.open;
    final data = InteractionScope.of(context);
    final p = data.palette;
    final panel = Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: p.raised,
        border: Border(left: BorderSide(color: p.border)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 24,
            offset: Offset(-6, 0),
          ),
        ],
      ),
      child: _content ?? widget.child,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escapeClose,
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: _t,
              child: GestureDetector(
                onTap: closing ? null : widget.onClose,
                child: ColoredBox(
                  color: p.isDark
                      ? const Color(0x88000000)
                      : const Color(0x44000000),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: closing,
              child: ExcludeSemantics(
                excluding: closing,
                child: Semantics(
                  scopesRoute: true,
                  explicitChildNodes: true,
                  namesRoute: true,
                  label: widget.semanticLabel,
                  child: ExcludeFocus(
                    excluding: closing,
                    child: FocusScope(
                      node: _scope,
                      child: AnimatedBuilder(
                        animation: _t,
                        child: RepaintBoundary(key: _keep, child: panel),
                        builder: (context, child) => _transition(data, child!),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _transition(InteractionData data, Widget child) {
    final v = _t.value;
    final closing = _t.status == AnimationStatus.reverse;
    if (v >= 1) return _settled(data, child);
    final c = closing
        ? SuiteMotion.exitCurve.transform(v)
        : SuiteMotion.curve.transform(v);
    final w = widget.width;
    switch (data.suite) {
      case InteractionSuite.standard:
        return FractionalTranslation(
          translation: Offset(1 - c, 0),
          child: child,
        );
      case InteractionSuite.rail:
        return FractionalTranslation(
          translation: Offset(1 - c, 0),
          child: _settled(data, child),
        );
      case InteractionSuite.scan:
        if (closing) {
          return Opacity(
            opacity: c,
            child: ClipRect(clipper: _FromRight(c), child: child),
          );
        }
        // A line at the edge first, then the panel opens from it.
        final line = (v / 0.35).clamp(0.0, 1.0);
        final open = SuiteMotion.curve.transform(
          ((v - 0.35) / 0.65).clamp(0.0, 1.0),
        );
        return SizedBox(
          width: w,
          child: Stack(
            children: [
              ClipRect(clipper: _FromRight(open), child: child),
              Positioned(
                right: w * open,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: FractionallySizedBox(
                    heightFactor: line,
                    child: Container(width: 2, color: data.palette.edge()),
                  ),
                ),
              ),
            ],
          ),
        );
      case InteractionSuite.glow:
        return Opacity(
          opacity: c,
          child: Transform.translate(
            offset: Offset(24 * (1 - c), 0),
            child: _settled(data, child, light: 1 - c),
          ),
        );
    }
  }

  Widget _settled(InteractionData data, Widget child, {double light = 0}) {
    final p = data.palette;
    switch (data.suite) {
      case InteractionSuite.rail:
        return CustomPaint(
          foregroundPainter: _EdgePainter((canvas, size) {
            canvas.drawRect(
              Rect.fromLTWH(0, 0, 2, size.height),
              Paint()..color = p.edge(),
            );
          }),
          child: child,
        );
      case InteractionSuite.scan:
        return CustomPaint(
          foregroundPainter: _EdgePainter((canvas, size) {
            paintBrackets(
              canvas,
              (Offset.zero & size).deflate(4),
              color: p.edge(0.8),
              length: 10,
            );
          }),
          child: child,
        );
      case InteractionSuite.glow:
        return CustomPaint(
          painter: _EdgePainter((canvas, size) {
            final r = Rect.fromLTWH(-30, 0, 60, size.height);
            canvas.drawRect(
              r,
              Paint()
                ..shader = LinearGradient(
                  colors: [p.light(0), p.light(0.25 + 0.3 * light), p.light(0)],
                ).createShader(r),
            );
          }),
          child: child,
        );
      case InteractionSuite.standard:
        return child;
    }
  }
}

class _FromRight extends CustomClipper<Rect> {
  _FromRight(this.f);
  final double f;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(size.width * (1 - f), 0, size.width * f, size.height);

  @override
  bool shouldReclip(_FromRight old) => old.f != f;
}

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.draw);
  final void Function(Canvas, Size) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}
