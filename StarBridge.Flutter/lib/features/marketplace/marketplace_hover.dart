import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../design_system/interaction/starbridge_action_row.dart';

import '../../design_system/styles/marketplace_palette.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_diagonal.dart';

/// The trading hall's hover (方案 E): the card lifts 2px, a direction-coloured
/// line with a slanted tail grows along its bottom edge, and after a short
/// pause an information drawer hangs from that edge. The drawer floats over
/// the next row (no layout shift), never covers the card's item image, shows
/// only data that is already loaded, and also opens for keyboard focus.
class MarketHoverCard extends StatefulWidget {
  const MarketHoverCard({
    required this.child,
    this.drawer,
    this.color,
    this.radius = 0,
    this.drawerWidth,
    this.alignEnd = false,
    this.lift = true,
    this.drawerKey,
    this.minDrawerWidth = 0,
    super.key,
  });
  final Widget child;

  /// Built lazily when the drawer opens, so it reads the latest state.
  final WidgetBuilder? drawer;

  /// Line and drawer edge colour; defaults to the accent.
  final Color? color;
  final double radius;

  /// Fixed drawer width (buttons); cards use their own width.
  final double? drawerWidth;

  /// Hang the drawer from the right edge (buttons at the end of a row).
  final bool alignEnd;
  final bool lift;
  final Key? drawerKey;

  /// Narrow tiles widen their drawer to at least this; it then gets a full
  /// outline since it no longer hangs flush from the card edge.
  final double minDrawerWidth;

  @override
  State<MarketHoverCard> createState() => _MarketHoverCardState();
}

class _MarketHoverCardState extends State<MarketHoverCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  bool _inCard = false, _inDrawer = false, _focused = false, _above = false;
  double _width = 0;
  Timer? _timer;

  bool get _active => _inCard || _inDrawer || _focused;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _sync() {
    if (!mounted) return;
    if (_still) {
      _hover.value = _active ? 1 : 0;
    } else {
      _active ? _hover.forward() : _hover.reverse();
    }
    _timer?.cancel();
    if (widget.drawer == null) return;
    if (_active && !_portal.isShowing) {
      // A short pause so sweeping across a grid does not flash every drawer.
      _timer = Timer(const Duration(milliseconds: 150), _show);
    } else if (!_active && _portal.isShowing) {
      // Grace period for the pointer to cross the 1px seam into the drawer.
      _timer = Timer(const Duration(milliseconds: 120), () {
        if (mounted && !_active) _portal.hide();
      });
    }
  }

  void _show() {
    if (!mounted || !_active) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached) {
      _width = box.size.width;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      // Open upward only when there is no room below; it then covers the row
      // above, still never this card's own image.
      _above = bottom + 180 > MediaQuery.sizeOf(context).height && top > 200;
    }
    setState(() {});
    _portal.show();
  }

  void close() {
    _timer?.cancel();
    _inDrawer = false;
    _inCard = false;
    if (_portal.isShowing) _portal.hide();
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.tokens.colors.accent;
    final card = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        _focused = focused;
        _sync();
      },
      child: MouseRegion(
        onEnter: (_) {
          _inCard = true;
          _sync();
        },
        onExit: (_) {
          _inCard = false;
          _sync();
        },
        child: AnimatedBuilder(
          animation: _hover,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, widget.lift ? -2 * _hover.value : 0),
            child: CustomPaint(
              foregroundPainter: _HoverEdgePainter(
                progress: Curves.easeOut.transform(_hover.value),
                color: color,
                outline: color.withValues(alpha: .38),
                radius: widget.radius,
              ),
              child: child,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
    if (widget.drawer == null) return card;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _drawer,
        child: card,
      ),
    );
  }

  Widget _drawer(BuildContext context) {
    final t = context.tokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = (widget.color ?? t.colors.accent).withValues(alpha: .38);
    final end = widget.alignEnd;
    final width = math.max(widget.drawerWidth ?? _width, widget.minDrawerWidth);
    final side = BorderSide(color: color);
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: _above
            ? (end ? Alignment.topRight : Alignment.topLeft)
            : (end ? Alignment.bottomRight : Alignment.bottomLeft),
        followerAnchor: _above
            ? (end ? Alignment.bottomRight : Alignment.bottomLeft)
            : (end ? Alignment.topRight : Alignment.topLeft),
        offset: Offset(0, _above ? -2 : (widget.drawerWidth == null ? 1 : 6)),
        child: MouseRegion(
          onEnter: (_) {
            _inDrawer = true;
            _sync();
          },
          onExit: (_) {
            _inDrawer = false;
            _sync();
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: _still ? 1 : 0, end: 1),
            duration: const Duration(milliseconds: 160),
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, (_above ? 6 : -6) * (1 - v)),
                child: child,
              ),
            ),
            child: _HoverScope(
              close: close,
              child: Material(
                key: widget.drawerKey,
                type: MaterialType.transparency,
                child: Container(
                  width: width,
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                  decoration: BoxDecoration(
                    color: dark ? MarketplacePalette.drawerDark : t.surfaces.raised.fill,
                    border: widget.drawerWidth != null || width > _width + 1
                        ? Border.fromBorderSide(side)
                        : Border(
                            left: side,
                            right: side,
                            top: _above ? side : BorderSide.none,
                            bottom: _above ? BorderSide.none : side,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: dark ? .75 : .18),
                        offset: const Offset(0, 14),
                        blurRadius: 24,
                        spreadRadius: -12,
                      ),
                    ],
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: t.colors.textSecondary,
                    ),
                    child: widget.drawer!(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverScope extends InheritedWidget {
  const _HoverScope({required this.close, required super.child});
  final VoidCallback close;
  @override
  bool updateShouldNotify(_HoverScope oldWidget) => false;
}

/// Grows the slanted bottom line and tints the outline with [progress].
class _HoverEdgePainter extends CustomPainter {
  const _HoverEdgePainter({
    required this.progress,
    required this.color,
    required this.outline,
    required this.radius,
  });
  final double progress, radius;
  final Color color, outline;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(.5), Radius.circular(radius)),
      Paint()
        ..color = outline.withValues(alpha: outline.a * progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    const h = 3.0;
    final width = size.width * progress;
    final run = marketSlantRun(h) * 2.3;
    if (width <= run) return;
    canvas.save();
    if (radius > 0) {
      canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    }
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - h)
        ..lineTo(width, size.height - h)
        ..lineTo(width - run, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HoverEdgePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.outline != outline ||
      old.radius != radius;
}

/// "比最低价　+20.5%": a label on the left, its value right-aligned.
class MarketDrawerRow extends StatelessWidget {
  const MarketDrawerRow(this.label, this.value, {this.color, this.mono = false, super.key});
  final String label;
  final Object value;
  final Color? color;
  final bool mono;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1),
          const SizedBox(width: 10),
          Expanded(
            child: value is Widget
                ? Align(alignment: Alignment.centerRight, child: value as Widget)
                : Text(
                    '$value',
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: color ?? t.colors.textPrimary,
                      fontFamily: mono ? t.typography.monoFamily : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A row of slanted quick actions at the bottom of a drawer.
class MarketDrawerActions extends StatelessWidget {
  const MarketDrawerActions(this.children, {super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(spacing: 4, runSpacing: 6, children: children),
  );
}

/// Small parallelogram action used in drawers. Closes the drawer it sits in
/// before running [onTap], so a dialog never opens under a floating drawer.
class MarketSlantButton extends StatelessWidget {
  const MarketSlantButton(
    this.label, {
    required this.onTap,
    this.color,
    this.filled = false,
    super.key,
  });
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tone = color ?? t.colors.accent;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Material(
        type: MaterialType.transparency,
        child: StarBridgeActionRow(
          inheritContentStyle: true,
          hoverFace: false,
          baseRadius: 0,
          // Close the drawer first, then act: a dialog never opens under a
          // drawer that is still floating.
          onActivate: enabled
              ? (_, _) {
                  context.getInheritedWidgetOfExactType<_HoverScope>()?.close();
                  onTap!();
                }
              : null,
          child: CustomPaint(
            painter: MarketParallelogramPainter(
              fill: filled ? tone : tone.withValues(alpha: .08),
              border: filled ? tone : t.colors.textSecondary.withValues(alpha: .45),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3.5),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: filled
                      ? (ThemeData.estimateBrightnessForColor(tone) == Brightness.dark
                          ? Colors.white
                          : MarketplacePalette.onAccent)
                      : t.colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
