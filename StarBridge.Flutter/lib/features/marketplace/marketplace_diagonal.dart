import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/styles/marketplace_palette.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

/// The trading hall's one diagonal: every slanted edge, divider and stripe
/// leans at the banner's angle (about 66 degrees from horizontal). Diagonals
/// are only used for dividers, labels and textures — never for panel corners.
const marketSlant = 24 * math.pi / 180;

/// Horizontal run of the slant over [height].
double marketSlantRun(double height) => height * math.tan(marketSlant);

Path _parallelogram(Size s) {
  final run = marketSlantRun(s.height);
  return Path()
    ..moveTo(run, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width - run, s.height)
    ..lineTo(0, s.height)
    ..close();
}

class MarketParallelogramPainter extends CustomPainter {
  const MarketParallelogramPainter({this.fill, this.border});
  final Color? fill, border;
  @override
  void paint(Canvas canvas, Size size) {
    final path = _parallelogram(size);
    if (fill != null) canvas.drawPath(path, Paint()..color = fill!);
    if (border != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = border!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(MarketParallelogramPainter old) =>
      old.fill != fill || old.border != border;
}

/// One slanted label segment. [solid] fills with [color]; otherwise a light
/// tint with a coloured outline, which is the hall's default label style.
class MarketSlantTag extends StatelessWidget {
  const MarketSlantTag(this.label, {required this.color, this.solid = false, this.mono, this.foil = false, super.key});
  final String label;
  final Color color;
  final bool solid;
  /// Optional numeric suffix set in the mono family (quality values).
  final String? mono;

  /// 极品 quality: a holographic foil with a slow sheen (still when motion
  /// is reduced) instead of the tinted outline (user 2026-10-23).
  final bool foil;
  @override
  Widget build(BuildContext context) {
    if (foil) return MarketFoilTag(label, mono: mono);
    final t = context.tokens;
    final foreground = solid ? MarketplacePalette.onGoldTag : color;
    final style = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: foreground, height: 1.2);
    return CustomPaint(
      painter: MarketParallelogramPainter(
        fill: solid ? color : color.withValues(alpha: .15),
        border: solid ? null : color.withValues(alpha: .62),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Text.rich(
          TextSpan(
            text: label,
            children: [
              if (mono != null)
                TextSpan(
                  text: ' $mono',
                  style: TextStyle(fontFamily: t.typography.monoFamily),
                ),
            ],
          ),
          style: style,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

/// The 极品 label: foil fill, a soft warm glow, and a white sheen crossing
/// every few seconds. One repaint boundary per tag keeps the frames local.
class MarketFoilTag extends StatefulWidget {
  const MarketFoilTag(this.label, {this.mono, super.key});
  final String label;
  final String? mono;
  @override
  State<MarketFoilTag> createState() => _MarketFoilTagState();
}

class _MarketFoilTagState extends State<MarketFoilTag>
    with SingleTickerProviderStateMixin {
  late final _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        InteractionScope.maybeOf(context)?.reduceMotion ??
        MediaQuery.maybeDisableAnimationsOf(context) ??
        false;
    if (still) {
      _phase
        ..stop()
        ..value = .3;
    } else if (!_phase.isAnimating) {
      _phase.repeat();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const ink = MarketplacePalette.foilInk;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _FoilPainter(_phase),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Text.rich(
            TextSpan(
              text: widget.label,
              children: [
                if (widget.mono != null)
                  TextSpan(
                    text: widget.label.isEmpty
                        ? widget.mono
                        : ' ${widget.mono}',
                    style: TextStyle(fontFamily: t.typography.monoFamily),
                  ),
              ],
            ),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: ink,
              height: 1.2,
            ),
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ),
    );
  }
}

class _FoilPainter extends CustomPainter {
  _FoilPainter(this.phase) : super(repaint: phase);
  final Animation<double> phase;
  @override
  void paint(Canvas canvas, Size size) {
    final path = _parallelogram(size);
    canvas.drawPath(
      path,
      Paint()
        ..color = MarketplacePalette.foilGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 5),
    );
    // The gradient is twice the tag's width and slides one width per cycle.
    final span = size.width * 2;
    final shift = -span / 2 * phase.value;
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: MarketplacePalette.foil,
          tileMode: TileMode.repeated,
        ).createShader(Rect.fromLTWH(shift, 0, span / 2, size.height)),
    );
    // Sheen: a narrow white band crossing in the first 60% of each cycle.
    final sweep = (phase.value * 1.6).clamp(0.0, 1.0);
    final x = -size.width * .4 + sweep * size.width * 1.8;
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: MarketplacePalette.foilSheen,
        ).createShader(Rect.fromLTWH(x, 0, size.width * .35, size.height)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FoilPainter old) => old.phase != phase;
}

/// Attribute tags joined along their shared slanted edge into one badge.
class MarketFusedTags extends StatelessWidget {
  const MarketFusedTags(this.tags, {super.key});
  final List<MarketSlantTag> tags;
  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    // Each segment overlaps the previous by its slant so the edges coincide.
    final overlap = marketSlantRun(18);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tags.length; i++)
          Transform.translate(offset: Offset(-overlap * i + i * 1.0, 0), child: tags[i]),
      ],
    );
  }
}

/// A short slanted hairline used between banner figures and between tabs.
class MarketSlantDivider extends StatelessWidget {
  const MarketSlantDivider({this.height = 22, this.color, super.key});
  final double height;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: marketSlantRun(height) + 2,
    height: height,
    child: CustomPaint(
      painter: _SlashPainter(color ?? context.tokens.colors.textSecondary.withValues(alpha: .4)),
    ),
  );
}

class _SlashPainter extends CustomPainter {
  const _SlashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawLine(
    Offset(size.width - 1, 0),
    Offset(1, size.height),
    Paint()
      ..color = color
      ..strokeWidth = 1,
  );
  @override
  bool shouldRepaint(_SlashPainter old) => old.color != color;
}

/// The section mark: two slanted bars in the accent colour before a heading.
class MarketHeadingMark extends StatelessWidget {
  const MarketHeadingMark({super.key});
  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.colors.accent;
    return SizedBox(
      width: 14,
      height: 16,
      child: CustomPaint(painter: _MarkPainter(accent)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final run = marketSlantRun(size.height);
    for (final (x, alpha) in [(0.0, 1.0), (5.0, .45)]) {
      canvas.drawPath(
        Path()
          ..moveTo(x + run, 0)
          ..lineTo(x + run + 3, 0)
          ..lineTo(x + 3, size.height)
          ..lineTo(x, size.height)
          ..close(),
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

/// Faint diagonal hatching (placeholders, hidden listings, loading).
class MarketHatchPainter extends CustomPainter {
  const MarketHatchPainter(this.color, {this.gap = 14, this.stroke = 6});
  final Color color;
  final double gap, stroke;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final run = marketSlantRun(size.height);
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke;
    for (var x = -run; x < size.width + run; x += gap) {
      canvas.drawLine(Offset(x + run, 0), Offset(x, size.height), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MarketHatchPainter old) => old.color != color;
}

/// The SCM plate's right edge and the glass slabs that lead into the dark
/// banner: three translucent parallelograms, each with a highlight edge.
class MarketGlassSlabs extends StatelessWidget {
  const MarketGlassSlabs({this.width = 150, super.key});
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: CustomPaint(painter: const _SlabPainter()),
  );
}

class _SlabPainter extends CustomPainter {
  const _SlabPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final run = marketSlantRun(size.height);
    for (final (x, alpha) in [(40.0, .95), (70.0, .65), (100.0, .38)]) {
      final path = Path()
        ..moveTo(x + run, 0)
        ..lineTo(x + run + 46, 0)
        ..lineTo(x + 46, size.height)
        ..lineTo(x, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              MarketplacePalette.glass.withValues(alpha: .26 * alpha),
              MarketplacePalette.glass.withValues(alpha: .07 * alpha),
            ],
          ).createShader(path.getBounds()),
      );
      canvas.drawLine(
        Offset(x + run, 0),
        Offset(x, size.height),
        Paint()
          ..color = MarketplacePalette.glassEdge.withValues(alpha: .7 * alpha)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_SlabPainter old) => false;
}

/// The light SCM plate: vertical left edge, slanted right edge, with the
/// SCM brand-orange slanted stroke just inside it.
class MarketPlateClipper extends CustomClipper<Path> {
  const MarketPlateClipper();
  @override
  Path getClip(Size size) {
    final run = marketSlantRun(size.height);
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - run, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(MarketPlateClipper old) => false;
}

class MarketPlateStripe extends CustomPainter {
  const MarketPlateStripe(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final run = marketSlantRun(size.height);
    final x = size.width - 30;
    canvas.drawPath(
      Path()
        ..moveTo(x, 0)
        ..lineTo(x + 4, 0)
        ..lineTo(x + 4 - run, size.height)
        ..lineTo(x - run, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(MarketPlateStripe old) => old.color != color;
}
