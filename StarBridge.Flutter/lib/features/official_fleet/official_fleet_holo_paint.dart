import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The client's diagonal anchor (-24deg), shared by the holo header pieces.
const double officialFleetHoloSkew = 24 * math.pi / 180;
final double officialFleetHoloSlant = math.tan(officialFleetHoloSkew);

/// How the header arrives: [full] once a day (the banner is unveiled along
/// the client slant), [quick] on later visits, [none] when it comes back
/// from a collapse or motion is reduced.
enum OfficialFleetHoloEntry { full, quick, none }

/// Entry lengths in milliseconds.
const int officialFleetHoloFullMs = 2400;
const int officialFleetHoloQuickMs = 420;

Animation<double> officialFleetHoloPhase(
  Animation<double> parent,
  int totalMs,
  int startMs,
  int durationMs, [
  Curve curve = Curves.easeOut,
]) => CurvedAnimation(
  parent: parent,
  curve: Interval(
    math.min(1, startMs / totalMs),
    math.min(1, (startMs + durationMs) / totalMs),
    curve: curve,
  ),
);

const Curve officialFleetHoloSettle = Cubic(.2, .8, .2, 1);

/// Glass slab: square left/top/bottom, right edge cut at the client slant.
class OfficialFleetSlantClipper extends CustomClipper<Path> {
  const OfficialFleetSlantClipper();

  @override
  Path getClip(Size size) {
    final run = size.height * officialFleetHoloSlant;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - run, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(OfficialFleetSlantClipper oldClipper) => false;
}

/// Emblem: one chamfered corner (bottom right), as in the trading-hall plate.
class OfficialFleetChamferClipper extends CustomClipper<Path> {
  const OfficialFleetChamferClipper(this.cut);

  final double cut;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height - cut)
    ..lineTo(size.width - cut, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(OfficialFleetChamferClipper oldClipper) =>
      oldClipper.cut != cut;
}

/// The lit slanted edge of the slab plus its top highlight. [grow] draws the
/// edge upwards from the bottom during entry; [fade] brings both in with the
/// glass, so no line floats over the banner before the slab is there.
class OfficialFleetSlabEdgePainter extends CustomPainter {
  OfficialFleetSlabEdgePainter({
    required this.grow,
    required this.accent,
    required this.highlight,
    this.fade,
  }) : super(repaint: fade == null ? grow : Listenable.merge([grow, fade]));

  final Animation<double> grow;
  final Animation<double>? fade;
  final Color accent, highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final run = size.height * officialFleetHoloSlant;
    final top = Offset(size.width, 0);
    final bottom = Offset(size.width - run, size.height);
    final t = grow.value;
    final f = (fade?.value ?? 1).clamp(0.0, 1.0);
    if (f <= 0) return;
    if (t > 0) {
      final start = Offset.lerp(bottom, top, t)!;
      canvas.drawLine(
        bottom,
        start,
        Paint()
          ..strokeWidth = 2
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: .9 * f),
              accent.withValues(alpha: accent.a * f),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawLine(
      Offset.zero,
      Offset(size.width * .95, 0),
      Paint()
        ..strokeWidth = 1
        ..shader = LinearGradient(
          colors: [
            highlight.withValues(alpha: .65 * f),
            highlight.withValues(alpha: .08 * f),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(OfficialFleetSlabEdgePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.highlight != highlight;
}

/// The banner unveiled from left to right behind an edge at the client
/// slant (top leading). At 1 the whole banner is shown.
class OfficialFleetUnveilClipper extends CustomClipper<Path> {
  OfficialFleetUnveilClipper(this.progress) : super(reclip: progress);

  final Animation<double> progress;

  static double edge(Size size, double t) =>
      (size.width + size.height * officialFleetHoloSlant) * t;

  @override
  Path getClip(Size size) {
    final t = progress.value;
    if (t >= 1) return Path()..addRect(Offset.zero & size);
    final top = edge(size, t);
    return Path()
      ..moveTo(0, 0)
      ..lineTo(top, 0)
      ..lineTo(top - size.height * officialFleetHoloSlant, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(OfficialFleetUnveilClipper oldClipper) =>
      oldClipper.progress != progress;
}

/// The lit edge riding the unveil: white into the fleet accent, gone at rest.
class OfficialFleetUnveilEdgePainter extends CustomPainter {
  OfficialFleetUnveilEdgePainter(this.progress, this.accent)
    : super(repaint: progress);

  final Animation<double> progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final top = OfficialFleetUnveilClipper.edge(size, t);
    final bottom = top - size.height * officialFleetHoloSlant;
    final fade = math.sin(math.pi * t);
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: .95 * fade),
        accent.withValues(alpha: fade),
      ],
    ).createShader(Offset.zero & size);
    canvas.drawLine(
      Offset(top, 0),
      Offset(bottom, size.height),
      Paint()
        ..strokeWidth = 2
        ..shader = shader,
    );
    // A soft glow trailing the edge so the reveal reads as light, not a cut.
    final glow = Path()
      ..moveTo(top - 36, 0)
      ..lineTo(top, 0)
      ..lineTo(bottom, size.height)
      ..lineTo(bottom - 36, size.height)
      ..close();
    canvas.drawPath(
      glow,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .18 * fade),
          ],
        ).createShader(Rect.fromLTRB(bottom - 36, 0, top, size.height)),
    );
  }

  @override
  bool shouldRepaint(OfficialFleetUnveilEdgePainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// A soft band of light passing down the mirror deck once as it powers on.
class OfficialFleetDeckScanPainter extends CustomPainter {
  OfficialFleetDeckScanPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    const band = 56.0;
    final y = (size.height + band) * t - band;
    final rect = Rect.fromLTWH(0, y, size.width, band);
    final fade = math.sin(math.pi * t);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .07 * fade),
            Colors.white.withValues(alpha: .16 * fade),
          ],
          stops: const [0, .8, 1],
        ).createShader(rect),
    );
    canvas.drawLine(
      Offset(0, y + band),
      Offset(size.width, y + band),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .28 * fade),
    );
  }

  @override
  bool shouldRepaint(OfficialFleetDeckScanPainter oldDelegate) => false;
}

/// One slanted glint that crosses the deck to close the full entry.
class OfficialFleetGlintPainter extends CustomPainter {
  OfficialFleetGlintPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final width = size.width * .14;
    final rise = size.height * officialFleetHoloSlant;
    final left = -width - rise + (size.width + width + rise * 2) * t;
    final band = Path()
      ..moveTo(left + rise, 0)
      ..lineTo(left + rise + width, 0)
      ..lineTo(left + width, size.height)
      ..lineTo(left, size.height)
      ..close();
    canvas.drawPath(
      band,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .12),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(left, 0, width + rise, size.height)),
    );
  }

  @override
  bool shouldRepaint(OfficialFleetGlintPainter oldDelegate) => false;
}

/// Skewed hairline used between metrics and inside tags.
class OfficialFleetSkewedDivider extends StatelessWidget {
  const OfficialFleetSkewedDivider({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Transform(
    alignment: Alignment.center,
    transform: Matrix4.skewX(-officialFleetHoloSkew),
    child: SizedBox(width: 1, child: ColoredBox(color: color)),
  );
}

/// Outlined parallelogram label (rank tag).
class OfficialFleetSkewTag extends StatelessWidget {
  const OfficialFleetSkewTag({
    required this.child,
    required this.color,
    super.key,
  });

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(-officialFleetHoloSkew),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: .5)),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
        child: child,
      ),
    ],
  );
}

/// Outline text with only the outer contour. A plain stroke also draws the
/// lines where a glyph's own contours overlap (the cross inside a bold "4");
/// here a twice-as-wide stroke is drawn and the filled glyph is then cut out
/// of it, leaving [strokeWidth] outside the letter and nothing inside.
///
/// The cut needs an offscreen layer, which Impeller would redo on every frame
/// anything on the page moves; so the result is drawn once into an image at
/// the screen's pixel ratio and only that image is painted afterwards
/// (performance, 2026-10-24).
class OfficialFleetOutlineText extends StatefulWidget {
  const OfficialFleetOutlineText(
    this.text, {
    required this.style,
    required this.color,
    this.strokeWidth = 1.2,
    this.fade = false,
    super.key,
  });

  final String text;
  final TextStyle style;
  final Color color;
  final double strokeWidth;

  /// Fade from opaque at 30% of the height to clear at the bottom, baked into
  /// the image (the SID's former mask layer).
  final bool fade;

  @override
  State<OfficialFleetOutlineText> createState() => _OutlineTextState();
}

class _OutlineTextState extends State<OfficialFleetOutlineText> {
  ui.Image? _image;
  Object? _key;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  TextPainter _layout(Paint paint, TextDirection direction) => TextPainter(
    text: TextSpan(
      text: widget.text,
      style: widget.style.copyWith(foreground: paint),
    ),
    textDirection: direction,
    maxLines: 1,
  )..layout();

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final probe = _layout(Paint(), direction);
    final pad = widget.strokeWidth * 2;
    final key = (
      widget.text,
      widget.style,
      widget.color,
      widget.strokeWidth,
      ratio,
      direction,
      widget.fade,
    );
    if (_image == null || _key != key) {
      _image?.dispose();
      _key = key;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..scale(ratio)
        ..translate(pad, pad);
      final bounds = (Offset.zero & probe.size).inflate(pad);
      canvas.saveLayer(bounds, Paint());
      _layout(
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = widget.strokeWidth * 2
          ..strokeJoin = StrokeJoin.round
          ..color = widget.color,
        direction,
      ).paint(canvas, Offset.zero);
      _layout(
        Paint()..blendMode = BlendMode.dstOut,
        direction,
      ).paint(canvas, Offset.zero);
      if (widget.fade) {
        canvas.drawRect(
          bounds,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [.3, 1],
              colors: [
                widget.color.withValues(alpha: 1),
                widget.color.withValues(alpha: 0),
              ],
            ).createShader(Offset.zero & probe.size),
        );
      }
      canvas.restore();
      final picture = recorder.endRecording();
      _image = picture.toImageSync(
        ((probe.width + pad * 2) * ratio).ceil(),
        ((probe.height + pad * 2) * ratio).ceil(),
      );
      picture.dispose();
    }
    return SizedBox.fromSize(
      size: probe.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -pad,
            top: -pad,
            child: RawImage(image: _image, scale: ratio),
          ),
        ],
      ),
    );
  }
}
