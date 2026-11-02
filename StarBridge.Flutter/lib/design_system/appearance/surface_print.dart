import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens/color_tokens.dart';

/// 印花里的一个图案。全部是细线稿，像暗纹壁纸一样淡淡印在底色上。
enum PrintMotif {
  snowflake,
  star,
  bell,
  bauble,
  holly,
  gift,
  dot,
  cobweb,
  bat,
  pumpkin,
  moon,
  ghost,
  spider,
}

/// 一块印花里的一个图案：放在哪里、多大、什么颜色。
@immutable
final class PrintStamp {
  const PrintStamp(
    this.motif, {
    required this.dx,
    required this.dy,
    required this.size,
    required this.color,
  });

  final PrintMotif motif;
  final double dx;
  final double dy;
  final double size;
  final Color color;
}

/// 一块可以平铺的印花，以及它印在各个面上的浓淡。
///
/// 印花本身没有动画，所以"减少动态效果"对它没有影响。
@immutable
final class SurfacePrintSpec {
  const SurfacePrintSpec({
    required this.tileWidth,
    required this.tileHeight,
    required this.stamps,
    required this.opacity,
    this.rotationDegrees = -10,
    this.strokeWidth = 1.1,
  });

  final double tileWidth;
  final double tileHeight;
  final List<PrintStamp> stamps;

  /// 每个面上的不透明度；没列出来的面不印。
  final Map<SurfaceRole, double> opacity;
  final double rotationDegrees;
  final double strokeWidth;

  double? opacityFor(SurfaceRole role) => opacity[role];
}

/// 一块预先画好的印花贴图。
///
/// 矢量线稿每帧重放很贵（一整个窗口上千笔），所以一块只画一次，之后每帧只是贴图。
/// 同一块印花、同样浓淡、同样缩放共用一张；最后一个使用者走了就释放。
final class _PrintTile {
  _PrintTile._(this._key, this.image);

  static final _live = <(SurfacePrintSpec, double, double), _PrintTile>{};

  // 线条很细、印花又转了一个小角度，缩放小于 2 倍时多画一倍，贴上去才和直接画一样清楚。
  static double _sampling(double devicePixelRatio) =>
      devicePixelRatio < 2 ? devicePixelRatio * 2 : devicePixelRatio;

  static _PrintTile acquire(
    SurfacePrintSpec spec,
    double opacity,
    double devicePixelRatio,
  ) {
    final key = (spec, opacity, _sampling(devicePixelRatio));
    final tile = _live[key] ??= _PrintTile._(
      key,
      _bake(spec, opacity, key.$3),
    );
    tile._users++;
    return tile;
  }

  static ui.Image _bake(SurfacePrintSpec spec, double opacity, double sampling) {
    final width = (spec.tileWidth * sampling).ceil();
    final height = (spec.tileHeight * sampling).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(width / spec.tileWidth, height / spec.tileHeight);
    // 压在边上的图案要从对边接回来，否则平铺时接缝处会断。
    for (var row = -1; row <= 1; row++) {
      for (var column = -1; column <= 1; column++) {
        _paintStamps(
          canvas,
          spec,
          opacity,
          Offset(column * spec.tileWidth, row * spec.tileHeight),
        );
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  final (SurfacePrintSpec, double, double) _key;
  final ui.Image image;
  int _users = 0;

  void release() {
    if (--_users > 0) return;
    _live.remove(_key);
    image.dispose();
  }
}

/// 把印花平铺到一个面上。只画，不响应任何输入。
class SurfacePrint extends StatefulWidget {
  const SurfacePrint({required this.spec, required this.role, super.key});

  final SurfacePrintSpec spec;
  final SurfaceRole role;

  @override
  State<SurfacePrint> createState() => _SurfacePrintState();
}

class _SurfacePrintState extends State<SurfacePrint> {
  _PrintTile? _tile;

  double? get _opacity {
    final opacity = widget.spec.opacityFor(widget.role);
    return opacity == null || opacity <= 0 ? null : opacity;
  }

  void _refresh() {
    final opacity = _opacity;
    final next = opacity == null
        ? null
        : _PrintTile.acquire(
            widget.spec,
            opacity,
            MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
          );
    _tile?.release();
    _tile = next;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  @override
  void didUpdateWidget(SurfacePrint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec || oldWidget.role != widget.role) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _tile?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = _opacity;
    if (opacity == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: Key('surface-print-${widget.role.name}'),
          painter: SurfacePrintPainter(
            widget.spec,
            opacity: opacity,
            tile: _tile?.image,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

void _paintStamps(
  Canvas canvas,
  SurfacePrintSpec spec,
  double opacity,
  Offset origin,
) {
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = spec.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final fill = Paint()..style = PaintingStyle.fill;
  for (final stamp in spec.stamps) {
    final color = stamp.color.withValues(alpha: opacity);
    stroke.color = color;
    fill.color = color;
    SurfacePrintPainter._motif(
      canvas,
      stamp.motif,
      origin + Offset(stamp.dx, stamp.dy),
      stamp.size,
      stroke,
      fill,
    );
  }
}

class SurfacePrintPainter extends CustomPainter {
  const SurfacePrintPainter(this.spec, {required this.opacity, this.tile});

  final SurfacePrintSpec spec;
  final double opacity;

  /// 预先画好的一块；没有时直接画矢量。
  final ui.Image? tile;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || opacity <= 0) return;
    // 整块面绕中心转一个小角度，图案才不会排成死板的格子。
    final radians = spec.rotationDegrees * math.pi / 180;
    final tile = this.tile;
    if (tile != null) {
      final transform = Matrix4.identity()
        ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
        ..rotateZ(radians)
        ..scaleByDouble(
          spec.tileWidth / tile.width,
          spec.tileHeight / tile.height,
          1,
          1,
        );
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.ImageShader(
            tile,
            TileMode.repeated,
            TileMode.repeated,
            transform.storage,
            filterQuality: FilterQuality.low,
          ),
      );
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(radians);
    // 从中心算，半条对角线外的都看不见。
    final reach =
        math.sqrt(size.width * size.width + size.height * size.height) / 2;
    final columns = (reach / spec.tileWidth).ceil() + 1;
    final rows = (reach / spec.tileHeight).ceil() + 1;
    for (var row = -rows; row <= rows; row++) {
      for (var column = -columns; column <= columns; column++) {
        _paintStamps(
          canvas,
          spec,
          opacity,
          Offset(column * spec.tileWidth, row * spec.tileHeight),
        );
      }
    }
    canvas.restore();
  }

  static void _motif(
    Canvas canvas,
    PrintMotif motif,
    Offset center,
    double size,
    Paint stroke,
    Paint fill,
  ) {
    switch (motif) {
      case PrintMotif.dot:
        canvas.drawCircle(center, size, fill);
      case PrintMotif.snowflake:
        _snowflake(canvas, center, size, stroke);
      case PrintMotif.star:
        canvas.drawPath(starBridgeStarPath(center, size), fill);
      case PrintMotif.bell:
        _bell(canvas, center, size, stroke);
      case PrintMotif.bauble:
        _bauble(canvas, center, size, stroke);
      case PrintMotif.holly:
        _holly(canvas, center, size, stroke, fill);
      case PrintMotif.gift:
        _gift(canvas, center, size, stroke);
      case PrintMotif.cobweb:
        _cobweb(canvas, center, size, stroke);
      case PrintMotif.bat:
        canvas.drawPath(_batPath(center, size), fill);
      case PrintMotif.pumpkin:
        _pumpkin(canvas, center, size, stroke);
      case PrintMotif.moon:
        _moon(canvas, center, size, stroke);
      case PrintMotif.ghost:
        _ghost(canvas, center, size, stroke, fill);
      case PrintMotif.spider:
        _spider(canvas, center, size, stroke, fill);
    }
  }

  /// 六臂雪花：三条过中心的线，每条两端各带一对短枝。
  static void _snowflake(Canvas canvas, Offset c, double r, Paint stroke) {
    for (var i = 0; i < 3; i++) {
      final angle = i * math.pi / 3 + math.pi / 2;
      final d = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(c - d * r, c + d * r, stroke);
      for (final sign in const [1.0, -1.0]) {
        final base = c + d * (r * .6 * sign);
        final back = math.atan2(d.dy * sign, d.dx * sign);
        for (final turn in const [1.0, -1.0]) {
          final b = back + turn * math.pi * .72;
          canvas.drawLine(
            base,
            base + Offset(math.cos(b), math.sin(b)) * (r * .3),
            stroke,
          );
        }
      }
    }
  }

  static void _bell(Canvas canvas, Offset c, double s, Paint stroke) {
    final path = Path()
      ..moveTo(c.dx - 8 * s, c.dy + 6 * s)
      ..cubicTo(
        c.dx - 8 * s,
        c.dy - 2 * s,
        c.dx - 6 * s,
        c.dy - 10 * s,
        c.dx,
        c.dy - 10 * s,
      )
      ..cubicTo(
        c.dx + 6 * s,
        c.dy - 10 * s,
        c.dx + 8 * s,
        c.dy - 2 * s,
        c.dx + 8 * s,
        c.dy + 6 * s,
      )
      ..lineTo(c.dx + 10 * s, c.dy + 9 * s)
      ..lineTo(c.dx - 10 * s, c.dy + 9 * s)
      ..close();
    canvas.drawPath(path, stroke);
    canvas.drawCircle(Offset(c.dx, c.dy + 11 * s), 2 * s, stroke);
    canvas.drawLine(
      Offset(c.dx - 2 * s, c.dy - 10 * s),
      Offset(c.dx, c.dy - 13 * s),
      stroke,
    );
    canvas.drawLine(
      Offset(c.dx, c.dy - 13 * s),
      Offset(c.dx + 2 * s, c.dy - 10 * s),
      stroke,
    );
  }

  static void _bauble(Canvas canvas, Offset c, double r, Paint stroke) {
    canvas.drawCircle(c, r, stroke);
    canvas.drawRect(
      Rect.fromLTWH(c.dx - r * .3, c.dy - r - 3, r * .6, 3),
      stroke,
    );
    final arc = Path()
      ..moveTo(c.dx - r * .7, c.dy - r * .25)
      ..quadraticBezierTo(c.dx, c.dy + r * .2, c.dx + r * .7, c.dy - r * .25);
    canvas.drawPath(arc, stroke);
  }

  /// 一对带尖的冬青叶加三颗实心浆果。
  static void _holly(
    Canvas canvas,
    Offset c,
    double s,
    Paint stroke,
    Paint fill,
  ) {
    Path leaf(double sign) {
      Offset p(double x, double y) => Offset(c.dx + sign * x * s, c.dy + y * s);
      return Path()
        ..moveTo(p(1, -1).dx, p(1, -1).dy)
        ..lineTo(p(5, -7).dx, p(5, -7).dy)
        ..lineTo(p(8, -4).dx, p(8, -4).dy)
        ..lineTo(p(12, -10).dx, p(12, -10).dy)
        ..lineTo(p(13, -4).dx, p(13, -4).dy)
        ..lineTo(p(18, -5).dx, p(18, -5).dy)
        ..lineTo(p(15, 1).dx, p(15, 1).dy)
        ..lineTo(p(18, 5).dx, p(18, 5).dy)
        ..lineTo(p(12, 5).dx, p(12, 5).dy)
        ..lineTo(p(10, 9).dx, p(10, 9).dy)
        ..lineTo(p(6, 5).dx, p(6, 5).dy)
        ..close();
    }

    canvas.drawPath(leaf(1), stroke);
    canvas.drawPath(leaf(-1), stroke);
    canvas.drawLine(
      Offset(c.dx + s, c.dy - s),
      Offset(c.dx + 10 * s, c.dy + 6 * s),
      stroke,
    );
    canvas.drawLine(
      Offset(c.dx - s, c.dy - s),
      Offset(c.dx - 10 * s, c.dy + 6 * s),
      stroke,
    );
    canvas.drawCircle(Offset(c.dx - 2 * s, c.dy + 3 * s), 2.2 * s, fill);
    canvas.drawCircle(Offset(c.dx + 3 * s, c.dy + 4 * s), 2 * s, fill);
    canvas.drawCircle(Offset(c.dx, c.dy + 7 * s), 1.8 * s, fill);
  }

  static void _gift(Canvas canvas, Offset c, double s, Paint stroke) {
    canvas.drawRect(
      Rect.fromLTWH(c.dx - 9 * s, c.dy - 4 * s, 18 * s, 13 * s),
      stroke,
    );
    canvas.drawRect(
      Rect.fromLTWH(c.dx - 10 * s, c.dy - 8 * s, 20 * s, 4 * s),
      stroke,
    );
    canvas.drawLine(
      Offset(c.dx, c.dy - 8 * s),
      Offset(c.dx, c.dy + 9 * s),
      stroke,
    );
    final bow = Path()
      ..moveTo(c.dx, c.dy - 8 * s)
      ..cubicTo(
        c.dx - 6 * s,
        c.dy - 14 * s,
        c.dx - 8 * s,
        c.dy - 9 * s,
        c.dx - 3 * s,
        c.dy - 8 * s,
      )
      ..moveTo(c.dx, c.dy - 8 * s)
      ..cubicTo(
        c.dx + 6 * s,
        c.dy - 14 * s,
        c.dx + 8 * s,
        c.dy - 9 * s,
        c.dx + 3 * s,
        c.dy - 8 * s,
      );
    canvas.drawPath(bow, stroke);
  }

  /// 八根辐条加三圈往里垂的丝；[r] 是半径。
  static void _cobweb(Canvas canvas, Offset c, double r, Paint stroke) {
    const spokes = 8;
    Offset at(int i, double radius) {
      final angle = i * 2 * math.pi / spokes;
      return c + Offset(math.cos(angle), math.sin(angle)) * radius;
    }

    for (var i = 0; i < spokes; i++) {
      canvas.drawLine(c, at(i, r), stroke);
    }
    for (final ring in const [.35, .68, 1.0]) {
      final start = at(0, r * ring);
      final path = Path()..moveTo(start.dx, start.dy);
      for (var i = 0; i < spokes; i++) {
        final mid = (i + .5) * 2 * math.pi / spokes;
        final sag = c + Offset(math.cos(mid), math.sin(mid)) * (r * ring * .78);
        final next = at(i + 1, r * ring);
        path.quadraticBezierTo(sag.dx, sag.dy, next.dx, next.dy);
      }
      canvas.drawPath(path, stroke);
    }
  }

  /// 实心蝙蝠剪影，翼展约 24×[s]。
  static Path _batPath(Offset c, double s) {
    Offset p(double x, double y) => Offset(c.dx + x * s, c.dy + y * s);
    final path = Path()..moveTo(p(0, -2.2).dx, p(0, -2.2).dy);
    void line(double x, double y) => path.lineTo(p(x, y).dx, p(x, y).dy);
    void quad(double cx, double cy, double x, double y) => path
        .quadraticBezierTo(p(cx, cy).dx, p(cx, cy).dy, p(x, y).dx, p(x, y).dy);
    line(-1.3, -4.4);
    line(-2.3, -1.8);
    quad(-6, -4.2, -12, -2.6);
    quad(-10.6, -1, -10.2, 1);
    quad(-8.8, -.2, -7.2, 1.4);
    quad(-5.6, .4, -4.2, 2.2);
    quad(-2.6, 1.6, 0, 4.2);
    quad(2.6, 1.6, 4.2, 2.2);
    quad(5.6, .4, 7.2, 1.4);
    quad(8.8, -.2, 10.2, 1);
    quad(10.6, -1, 12, -2.6);
    quad(6, -4.2, 2.3, -1.8);
    line(1.3, -4.4);
    return path..close();
  }

  /// 南瓜：外轮廓、中间一瓣、瓜蒂和一小圈藤。没有脸。
  static void _pumpkin(Canvas canvas, Offset c, double s, Paint stroke) {
    canvas.drawOval(
      Rect.fromCenter(center: c, width: 20 * s, height: 15 * s),
      stroke,
    );
    canvas.drawOval(
      Rect.fromCenter(center: c, width: 9 * s, height: 15 * s),
      stroke,
    );
    final stem = Path()
      ..moveTo(c.dx - s, c.dy - 7.3 * s)
      ..lineTo(c.dx - .6 * s, c.dy - 10.5 * s)
      ..lineTo(c.dx + 1.4 * s, c.dy - 10.8 * s)
      ..lineTo(c.dx + s, c.dy - 7.3 * s)
      ..moveTo(c.dx + 1.4 * s, c.dy - 9.6 * s)
      ..quadraticBezierTo(
        c.dx + 5.5 * s,
        c.dy - 12.5 * s,
        c.dx + 4.6 * s,
        c.dy - 8.4 * s,
      );
    canvas.drawPath(stem, stroke);
  }

  /// 月牙；[r] 是外圆半径。
  static void _moon(Canvas canvas, Offset c, double r, Paint stroke) {
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      Path()..addOval(
        Rect.fromCircle(center: c + Offset(r * .45, -r * .2), radius: r * .85),
      ),
    );
    canvas.drawPath(crescent, stroke);
  }

  /// 小幽灵：圆顶、波浪下摆、两只实心眼睛。
  static void _ghost(
    Canvas canvas,
    Offset c,
    double s,
    Paint stroke,
    Paint fill,
  ) {
    Offset p(double x, double y) => Offset(c.dx + x * s, c.dy + y * s);
    final body = Path()
      ..moveTo(p(-7, 8).dx, p(-7, 8).dy)
      ..lineTo(p(-7, -2).dx, p(-7, -2).dy)
      ..cubicTo(
        p(-7, -11).dx,
        p(-7, -11).dy,
        p(7, -11).dx,
        p(7, -11).dy,
        p(7, -2).dx,
        p(7, -2).dy,
      )
      ..lineTo(p(7, 8).dx, p(7, 8).dy);
    // 下摆四道波浪，从右往左。
    for (var i = 0; i < 4; i++) {
      final x = 7 - i * 3.5;
      final ctrl = p(x - 1.75, i.isEven ? 10.5 : 5.5);
      final end = p(x - 3.5, 8);
      body.quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
    }
    canvas.drawPath(body..close(), stroke);
    canvas.drawCircle(p(-2.5, -2), 1.1 * s, fill);
    canvas.drawCircle(p(2.5, -2), 1.1 * s, fill);
  }

  /// 吊在一根丝上的小蜘蛛。
  static void _spider(
    Canvas canvas,
    Offset c,
    double s,
    Paint stroke,
    Paint fill,
  ) {
    Offset p(double x, double y) => Offset(c.dx + x * s, c.dy + y * s);
    canvas.drawLine(p(0, -16), p(0, -3), stroke);
    canvas.drawCircle(c, 2.4 * s, fill);
    canvas.drawCircle(p(0, -2.9), 1.4 * s, fill);
    for (final sign in const [1.0, -1.0]) {
      for (final y in const [-1.6, -.4, .8, 2.0]) {
        final knee = p(sign * 4.6, y < 0 ? y - 2.4 : y - 1.2);
        canvas.drawLine(p(sign * 1.6, y * .7), knee, stroke);
        canvas.drawLine(knee, p(sign * 6.4, y + 1.6), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(SurfacePrintPainter oldDelegate) =>
      oldDelegate.spec != spec ||
      oldDelegate.opacity != opacity ||
      oldDelegate.tile != tile;
}

/// 星桥的四角星，和品牌标同一个轮廓；[size] 是半径。
Path starBridgeStarPath(Offset center, double size) {
  // 品牌标按 100×100 的框画，这里缩放到以 center 为中心、半径 size。
  final k = size / 42;
  Offset p(double x, double y) =>
      Offset(center.dx + (x - 50) * k, center.dy + (y - 50) * k);
  return Path()
    ..moveTo(p(50, 8).dx, p(50, 8).dy)
    ..cubicTo(
      p(52.5, 38).dx,
      p(52.5, 38).dy,
      p(58, 46).dx,
      p(58, 46).dy,
      p(90, 50).dx,
      p(90, 50).dy,
    )
    ..cubicTo(
      p(58, 54).dx,
      p(58, 54).dy,
      p(52.5, 62).dx,
      p(52.5, 62).dy,
      p(50, 92).dx,
      p(50, 92).dy,
    )
    ..cubicTo(
      p(47.5, 62).dx,
      p(47.5, 62).dy,
      p(42, 54).dx,
      p(42, 54).dy,
      p(10, 50).dx,
      p(10, 50).dy,
    )
    ..cubicTo(
      p(42, 46).dx,
      p(42, 46).dy,
      p(47.5, 38).dx,
      p(47.5, 38).dy,
      p(50, 8).dx,
      p(50, 8).dy,
    )
    ..close();
}
