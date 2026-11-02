import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';

/// Image viewer with zoom, pan and an optional crop frame.
///
/// Wheel/pinch zoom and drag pan follow the pointer directly (Flutter's
/// [InteractiveViewer]); the toolbar's zoom buttons animate the scale a
/// short way. The zoom readout is always the real value. In crop mode the
/// four corner handles follow the pointer exactly; the frame shows the
/// suite's mark (rail: lit edges, scan: bracket corners, glow: soft edge)
/// and the output rect is reported in image fractions, untouched by any
/// animation. Keyboard-activated toolbar buttons and reduced motion jump
/// straight to the target; turning reduced motion on mid-zoom lands on the
/// target at once.
///
/// Rotation turns clockwise in 90° steps and always fits the turned image
/// inside the frame (no clipping, no jump in size): a pointer turn eases a
/// quarter turn, repeated presses keep turning from where the image is;
/// keyboard and reduced motion land on the new angle at once.
/// [quarterTurns] is the real orientation, reported via [onRotationChanged].
class SuiteImageViewer extends StatefulWidget {
  const SuiteImageViewer({
    required this.image,
    this.onCropChanged,
    this.onRotationChanged,
    this.height = 220,
    super.key,
  });

  final Widget image;
  final ValueChanged<Rect>? onCropChanged;
  final ValueChanged<int>? onRotationChanged;
  final double height;

  @override
  State<SuiteImageViewer> createState() => SuiteImageViewerState();
}

class SuiteImageViewerState extends State<SuiteImageViewer>
    with TickerProviderStateMixin {
  final _view = TransformationController();
  late final _zoomAnim = AnimationController(vsync: this);

  /// Displayed rotation in quarter turns (fractional while turning). Keeps
  /// counting up so every turn goes clockwise.
  late final _turn = AnimationController.unbounded(vsync: this);
  int _turnTarget = 0;

  /// The image's real orientation: 0–3 quarter turns clockwise.
  int get quarterTurns => _turnTarget % 4;
  Animation<Matrix4>? _tween;
  Matrix4? _target;
  bool _crop = false;

  /// The image stage's size, measured inside the fixed-height stage (so the
  /// viewer still reports intrinsic sizes, e.g. inside IntrinsicHeight).
  Size _size = Size.zero;

  /// Crop rect in fractions of the viewer (0–1).
  Rect crop = const Rect.fromLTRB(0.15, 0.15, 0.85, 0.85);

  double get scale => _view.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _zoomAnim.addListener(() {
      final t = _tween;
      if (t != null) _view.value = t.value;
    });
    _view.addListener(() => setState(() {}));
  }

  /// Turns the image a quarter turn clockwise.
  void rotate({InteractionSource source = InteractionSource.pointer}) {
    _turnTarget++;
    final data = InteractionScope.of(context);
    if (!data.animates || source == InteractionSource.keyboard) {
      _turn.value = _turnTarget.toDouble();
    } else {
      _turn.animateTo(
        _turnTarget.toDouble(),
        duration: const Duration(milliseconds: 240),
        curve: SuiteMotion.curve,
      );
    }
    setState(() {});
    widget.onRotationChanged?.call(quarterTurns);
  }

  /// Scale that fits a [size] image turned by [turns] inside [size].
  static double _fit(Size size, double turns) {
    final a = turns * math.pi / 2;
    final c = math.cos(a).abs(), s = math.sin(a).abs();
    final w = size.width * c + size.height * s;
    final h = size.width * s + size.height * c;
    return math.min(size.width / w, size.height / h);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final target = _target;
    if (!InteractionScope.of(context).animates &&
        _zoomAnim.isAnimating &&
        target != null) {
      _zoomAnim.stop();
      _tween = null;
      _view.value = target;
    }
    if (!InteractionScope.of(context).animates && _turn.isAnimating) {
      _turn.value = _turnTarget.toDouble();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    _zoomAnim.dispose();
    _view.dispose();
    super.dispose();
  }

  /// Zooms around the centre to [target] (toolbar buttons). Keyboard
  /// [source] jumps.
  void zoomTo(
    double target,
    Size size, {
    InteractionSource source = InteractionSource.pointer,
  }) {
    final data = InteractionScope.of(context);
    final s = target.clamp(1.0, 4.0);
    final c = size.center(Offset.zero);
    final end = Matrix4.identity()
      ..translateByDouble(c.dx * (1 - s), c.dy * (1 - s), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
    _target = end;
    if (!data.animates || source == InteractionSource.keyboard) {
      _zoomAnim.stop();
      _tween = null;
      _view.value = end;
      return;
    }
    _tween = Matrix4Tween(
      begin: _view.value,
      end: end,
    ).animate(CurvedAnimation(parent: _zoomAnim, curve: SuiteMotion.curve));
    _zoomAnim
      ..duration = const Duration(milliseconds: 220)
      ..forward(from: 0);
  }

  void _dragCorner(int corner, Offset delta, Size size) {
    final dx = delta.dx / size.width, dy = delta.dy / size.height;
    var r = crop;
    const min = 0.12;
    switch (corner) {
      case 0:
        r = Rect.fromLTRB(
          (r.left + dx).clamp(0, r.right - min),
          (r.top + dy).clamp(0, r.bottom - min),
          r.right,
          r.bottom,
        );
      case 1:
        r = Rect.fromLTRB(
          r.left,
          (r.top + dy).clamp(0, r.bottom - min),
          (r.right + dx).clamp(r.left + min, 1),
          r.bottom,
        );
      case 2:
        r = Rect.fromLTRB(
          (r.left + dx).clamp(0, r.right - min),
          r.top,
          r.right,
          (r.bottom + dy).clamp(r.top + min, 1),
        );
      default:
        r = Rect.fromLTRB(
          r.left,
          r.top,
          (r.right + dx).clamp(r.left + min, 1),
          (r.bottom + dy).clamp(r.top + min, 1),
        );
    }
    setState(() => crop = r);
    widget.onCropChanged?.call(r);
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    Widget tool(
      IconData icon,
      String label,
      ValueChanged<InteractionSource>? onTap, {
      bool selected = false,
    }) => SuitePressable(
      kind: PressableKind.tab,
      selected: selected,
      minHeight: 28,
      baseRadius: 4,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      semanticLabel: label,
      onActivate: onTap,
      child: Icon(icon, size: 16, color: selected ? p.accent : null),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        ClipRRect(
          borderRadius: suiteRadius(data.suite, 6),
          child: SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, widget.height);
                _size = size;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        transformationController: _view,
                        minScale: 1,
                        maxScale: 4,
                        panEnabled: !_crop,
                        scaleEnabled: !_crop,
                        child: SizedBox.fromSize(
                          size: size,
                          child: AnimatedBuilder(
                            animation: _turn,
                            child: widget.image,
                            builder: (context, child) {
                              final t = _turn.value;
                              if (t == 0) return child!;
                              final k = _fit(size, t);
                              return Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..rotateZ(t * math.pi / 2)
                                  ..scaleByDouble(k, k, 1, 1),
                                child: child,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    if (_crop) ..._cropLayer(data, size),
                  ],
                );
              },
            ),
          ),
        ),
        Row(
          spacing: 4,
          children: [
            tool(
              Icons.zoom_out,
              '缩小',
              scale > 1.01
                  ? (src) => zoomTo(scale / 1.5, _size, source: src)
                  : null,
            ),
            SizedBox(
              width: 46,
              child: Text(
                '${(scale * 100).round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: p.textSecondary,
                ),
              ),
            ),
            tool(
              Icons.zoom_in,
              '放大',
              scale < 3.99
                  ? (src) => zoomTo(scale * 1.5, _size, source: src)
                  : null,
            ),
            tool(
              Icons.fit_screen_outlined,
              '适应窗口',
              scale > 1.01 ? (src) => zoomTo(1, _size, source: src) : null,
            ),
            const Spacer(),
            tool(
              Icons.rotate_right,
              '向右旋转（当前 ${quarterTurns * 90}°）',
              (src) => rotate(source: src),
            ),
            tool(
              Icons.crop,
              _crop ? '完成裁切' : '裁切',
              (_) => setState(() => _crop = !_crop),
              selected: _crop,
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _cropLayer(InteractionData data, Size size) {
    final p = data.palette;
    final r = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final corners = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: _CropPainter(data, r)),
        ),
      ),
      for (var i = 0; i < 4; i++)
        Positioned(
          left: corners[i].dx - 12,
          top: corners[i].dy - 12,
          child: Semantics(
            label: '裁切角 ${i + 1}',
            child: MouseRegion(
              cursor: i == 0 || i == 3
                  ? SystemMouseCursors.resizeUpLeftDownRight
                  : SystemMouseCursors.resizeUpRightDownLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => _dragCorner(i, d.delta, size),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: data.suite == InteractionSuite.scan
                            ? BoxShape.rectangle
                            : BoxShape.circle,
                        border: Border.all(color: p.accent, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.data, this.r);
  final InteractionData data;
  final Rect r;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.8),
    );
    switch (data.suite) {
      case InteractionSuite.rail:
        canvas.drawRect(
          Rect.fromLTWH(r.left, r.top - 1, r.width, 2),
          Paint()..color = p.edge(),
        );
        canvas.drawRect(
          Rect.fromLTWH(r.left, r.bottom - 1, r.width, 2),
          Paint()..color = p.edge(),
        );
      case InteractionSuite.scan:
        paintBrackets(
          canvas,
          r.inflate(3),
          color: p.edge(),
          length: 14,
          width: 2.5,
        );
        // Thirds grid: the "rangefinder" of the crop.
        final g = Paint()..color = Colors.white.withValues(alpha: 0.25);
        for (var i = 1; i < 3; i++) {
          canvas.drawRect(
            Rect.fromLTWH(r.left + r.width * i / 3, r.top, 1, r.height),
            g,
          );
          canvas.drawRect(
            Rect.fromLTWH(r.left, r.top + r.height * i / 3, r.width, 1),
            g,
          );
        }
      case InteractionSuite.glow:
        paintGlowStrokes(canvas, RRect.fromRectXY(r, 2, 2), p.edge(), 0.7);
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.r != r || old.data != data;
}
