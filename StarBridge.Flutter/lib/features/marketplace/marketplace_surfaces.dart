import '../../design_system/styles/marketplace_palette.dart';
import '../../design_system/interaction/starbridge_choice_navigation.dart';
import '../../design_system/interaction/starbridge_tracked_navigation.dart';
import 'marketplace_diagonal.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

Color marketLine(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? MarketplacePalette.lineDark
    : MarketplacePalette.lineLight;

/// Static surface treatment shared by the trading hall, catalogue and order book.
class MarketSurface extends StatefulWidget {
  const MarketSurface({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.corners = true,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool corners;
  @override
  State<MarketSurface> createState() => _MarketSurfaceState();
}

class _MarketSurfaceState extends State<MarketSurface> {
  @override
  // One flat, square-cornered panel everywhere (the hall's language, 2026-10-20).
  // The old rounded frame with corner marks is retired; [MarketSurface.corners]
  // is kept for callers but no longer draws anything. Cards take their hover
  // from MarketHoverCard.
  Widget build(BuildContext context) => CustomPaint(
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: marketLine(context)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .55],
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: .03),
              context.tokens.surfaces.panel.fill,
            ),
            context.tokens.surfaces.panel.fill,
          ],
        ),
      ),
      child: CustomPaint(
        foregroundPainter: _TopHighlight(
          Theme.of(context).brightness == Brightness.dark ? .045 : .9,
        ),
        child: Padding(padding: widget.padding, child: widget.child),
      ),
    ),
  );
}

class _TopHighlight extends CustomPainter {
  const _TopHighlight(this.alpha);
  final double alpha;
  @override
  void paint(Canvas canvas, Size s) => canvas.drawLine(
    const Offset(10, 1),
    Offset(s.width - 10, 1),
    Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..strokeWidth = 1,
  );
  @override
  bool shouldRepaint(_TopHighlight old) => old.alpha != alpha;
}

class MarketMarks extends CustomPainter {
  const MarketMarks(this.color, {this.ruler = false});
  final Color color;
  final bool ruler;
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    if (ruler) {
      canvas.drawLine(Offset(0, s.height), Offset(48, s.height), p);
      p
        ..strokeWidth = 1
        ..color = color.withValues(alpha: .45);
      for (double x = (s.width - 120).clamp(0, s.width); x < s.width; x += 8) {
        canvas.drawLine(Offset(x, s.height), Offset(x, s.height + 4), p);
      }
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(0, 10)
          ..lineTo(0, 0)
          ..lineTo(10, 0),
        p,
      );
      canvas.drawPath(
        Path()
          ..moveTo(s.width - 10, s.height)
          ..lineTo(s.width, s.height)
          ..lineTo(s.width, s.height - 10),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(MarketMarks old) =>
      old.color != color || old.ruler != ruler;
}

/// Section heading in the trading hall's diagonal language: a slanted mark,
/// the title, then a hairline fading to the right. No decorative English
/// (user, 10-29: “页面内最好不要装饰性英文”).
class MarketHeading extends StatelessWidget {
  const MarketHeading(
    this.title, {
    this.trailing,
    this.leading,
    this.titleSize = 16,
    super.key,
  });
  final String title;
  final Widget? trailing, leading;
  final double titleSize;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return CustomPaint(
      foregroundPainter: _FadeLine(t.colors.textSecondary),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          children: [
            const MarketHeadingMark(),
            const SizedBox(width: 9),
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Text(
              title,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
                color: t.colors.textPrimary,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              Flexible(child: trailing!),
            ],
          ],
        ),
      ),
    );
  }
}

class _FadeLine extends CustomPainter {
  const _FadeLine(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, size.height - 1, size.width, 1);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: .38),
            color.withValues(alpha: .10),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_FadeLine old) => old.color != color;
}

class MarketGrid extends CustomPainter {
  const MarketGrid(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color.withValues(alpha: .07)
      ..strokeWidth = 1;
    for (double x = 0; x < s.width; x += 14) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
    for (double y = 0; y < s.height; y += 14) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
  }

  @override
  bool shouldRepaint(MarketGrid old) => old.color != color;
}

class MarketTabs extends StatelessWidget {
  const MarketTabs({
    required this.choices,
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final List<StarBridgeNavigationChoice> choices;
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => StarBridgeTrackedNavigation(
    items: [
      for (final choice in choices)
        TrackItem(id: choice.id, label: choice.label, enabled: choice.enabled),
    ],
    selected: selected,
    onSelected: onSelected,
    spacing: 8,
    // The divider sits between targets, not inside one: the suite's
    // selection frame measures the target and must centre on its text.
    separator: const Padding(
      padding: EdgeInsets.only(right: 8),
      child: MarketSlantDivider(height: 14),
    ),
    // The hall's tab language: text, slanted dividers and a short underline
    // with a slanted tail; no filled block.
    targetBuilder: (context, item, selected, focus, activate) => Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          focusNode: focus,
          onTap: item.enabled
              ? () => activate(InteractionSource.pointer)
              : null,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? context.tokens.colors.textPrimary
                        : context.tokens.colors.textSecondary,
                  ),
                  child: choices.firstWhere((c) => c.id == item.id).child,
                ),
                const SizedBox(height: 4),
                ClipPath(
                  clipper: const _UnderlineTail(),
                  child: Container(
                    height: 2,
                    width: selected ? 22 : 0,
                    color: context.tokens.colors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _UnderlineTail extends CustomClipper<Path> {
  const _UnderlineTail();
  @override
  Path getClip(Size size) {
    final run = marketSlantRun(size.height) * 2;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo((size.width - run).clamp(0, size.width), size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_UnderlineTail oldClipper) => false;
}
