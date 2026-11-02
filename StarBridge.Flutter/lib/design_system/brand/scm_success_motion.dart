import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/starbridge_tokens.dart';
import 'scm_brand_mark.dart';

/// Native rendering of the approved SCM intro V3 success timeline (2.2 s).
/// Keeps original PNG pixels, seven components, pivot and reveal timings.
class ScmSuccessMotion extends StatefulWidget {
  const ScmSuccessMotion({
    required this.play,
    this.loading = false,
    this.brief = false,
    super.key,
  });
  final bool play;
  final bool loading;
  final bool brief;

  @visibleForTesting
  static Future<void> verifyArtwork() async {
    await _ScmSuccessMotionState._artwork();
  }

  @override
  State<ScmSuccessMotion> createState() => _ScmSuccessMotionState();
}

class _ScmSuccessMotionState extends State<ScmSuccessMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
    value: 1,
  );
  // The bundled artwork is immutable and shared for the process lifetime.
  // Resolve a failed first load to null so a later widget can retry without
  // introducing a reassignable global cache or caching an error forever.
  static final Future<_Artwork?> _initialArtwork = _Artwork.load()
      .then<_Artwork?>((art) => art, onError: (Object _, StackTrace _) => null);

  static Future<_Artwork> _artwork() async =>
      await _initialArtwork ?? await _Artwork.load();
  _Artwork? _art;
  bool _started = false;
  bool _failed = false;
  bool? _lastReduced;
  double? _loadingEnd;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final art = await _artwork();
      if (!mounted) return;
      setState(() => _art = art);
      _start();
    } catch (_) {
      // Static brand fallback; branding cannot block login.
      if (mounted) setState(() => _failed = true);
    }
  }

  bool get _reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      context.tokens.motion.surfaceEnter == Duration.zero;

  void _start() {
    if (_started || _art == null) return;
    _started = true;
    _run();
  }

  void _run() {
    if (_reduced) {
      _clock.value = 1;
      return;
    }
    if (widget.loading) {
      _clock.repeat(period: const Duration(seconds: 20));
    } else if (widget.play) {
      _clock.duration = Duration(
        milliseconds: widget.brief
            ? 650
            : _loadingEnd != null
            ? 2800
            : 2200,
      );
      _clock.forward(from: 0);
    } else {
      _clock.value = 1;
    }
  }

  @override
  void didUpdateWidget(ScmSuccessMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading || oldWidget.play != widget.play) {
      _loadingEnd = oldWidget.loading && !widget.loading
          ? _clock.value * 20
          : null;
      if (_art != null) _run();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = _reduced;
    final resumeWaiting = _lastReduced == true && !reduced && widget.loading;
    _lastReduced = reduced;
    if (reduced) _clock.value = 1;
    // Resume only an ongoing wait. Do not replay an already settled success.
    if (resumeWaiting && _started && _art != null) _run();
    _start();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'SCM',
    image: true,
    child: SizedBox(
      width: 180,
      height: 72,
      child: _art == null
          ? widget.play && !_failed
                ? const SizedBox.shrink()
                : const Center(child: ScmBrandMark())
          : RepaintBoundary(
              child: CustomPaint(
                painter: _ScmPainter(
                  _art!,
                  _clock,
                  loading: widget.loading,
                  brief: widget.brief,
                  loadingEnd: _loadingEnd,
                  reduced: _reduced,
                ),
              ),
            ),
    ),
  );
}

double _phase(double t, double a, double b) => ((t - a) / (b - a)).clamp(0, 1);
double _out(double x) => 1 - math.pow(1 - x.clamp(0, 1), 3).toDouble();
double _smooth(double x) => x * x * (3 - 2 * x);
double _mix(double a, double b, double p) => a + (b - a) * p;

@visibleForTesting
double scmV3Alignment(double t, double a, double b, double start) {
  final p = _phase(t, a, b);
  if (p < .57) return _mix(start, start * .19, _out(p / .57));
  if (p < .70) return start * .19;
  if (p < .86) {
    return _mix(start * .19, -start.sign * .65, _smooth((p - .70) / .16));
  }
  return _mix(-start.sign * .65, 0, _out((p - .86) / .14));
}

class _ScmPainter extends CustomPainter {
  _ScmPainter(
    this.art,
    this.clock, {
    required this.loading,
    required this.brief,
    required this.loadingEnd,
    required this.reduced,
  }) : super(repaint: clock);
  final _Artwork art;
  final Animation<double> clock;
  final bool loading, brief, reduced;
  final double? loadingEnd;

  @override
  void paint(Canvas canvas, Size size) {
    // Crop the original 960x540 stage to its brand lockup, without changing
    // mark/wordmark relative size, placement or rotation origin.
    final scale = math.min(size.width / 560, size.height / 240);
    canvas.save();
    canvas.translate(
      (size.width - 560 * scale) / 2,
      (size.height - 240 * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-238, -150);
    final elapsed = clock.value * (loadingEnd != null ? 2.8 : 2.2);
    final t = brief
        ? 1 + clock.value * 1.2
        : loadingEnd != null
        ? math.max(0.0, elapsed - .6)
        : elapsed;
    double normalized(double angle) => (angle + 180) % 360 - 180;
    final end = loadingEnd;
    var ring = _mix(
      end != null || brief ? .84 : .06,
      1,
      _out(_phase(t, .15, .95)),
    );
    var core = _out(_phase(t, 1.14, 1.48));
    var word = _out(_phase(t, 1.42, 2.02));
    var outer = scmV3Alignment(
      t,
      .25,
      1.26,
      end == null ? -18 : normalized(-18 + 72 * (end + .3)),
    );
    var inner = scmV3Alignment(
      t,
      .36,
      1.30,
      end == null ? 15 : normalized(15 - 90 * (end + .3)),
    );
    final braking = !loading && end != null && elapsed < .6;
    if (loading || braking) {
      final q = (elapsed / .6).clamp(0.0, 1.0);
      final seconds = loading ? clock.value * 20 : end! + .6 * (q - q * q / 2);
      outer = reduced ? 0 : -18 + 72 * seconds;
      inner = reduced ? 0 : 15 - 90 * seconds;
      ring = .84;
      core = 0;
      word = 0;
    }
    void draw(
      ui.Image image,
      double angle,
      double alpha, {
      bool screen = false,
    }) {
      if (alpha <= 0) return;
      canvas.save();
      canvas.translate(259, 171);
      canvas.scale(182 / art.mark.width);
      canvas.translate(art.mark.width / 2, 550);
      canvas.rotate(angle * math.pi / 180);
      canvas.translate(-art.mark.width / 2, -550);
      canvas.drawImage(
        image,
        Offset.zero,
        Paint()
          ..filterQuality = FilterQuality.high
          ..color = Colors.white.withValues(alpha: alpha)
          ..blendMode = screen ? BlendMode.screen : BlendMode.srcOver,
      );
      canvas.restore();
    }

    if (clock.value == 1 && !loading) {
      draw(art.mark, 0, 1);
    } else {
      final dock = loading || braking
          ? 0.0
          : math.exp(-math.pow((t - 1.31) / .115, 2));
      for (var i = 0; i < 3; i++) {
        final angle = i == 0
            ? 0.0
            : i == 1
            ? inner
            : outer;
        final alpha = i == 0 ? core : ring;
        draw(art.layers[i], angle, alpha);
        if (dock > .01) {
          draw(art.layers[i], angle, alpha * dock * .15, screen: true);
        }
      }
    }
    if (word > 0) {
      final height = 292 * art.word.height / art.word.width;
      final y = 268 - height / 2;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(484, y - 8, 292 * word, height + 16));
      canvas.drawImageRect(
        art.word,
        Rect.fromLTWH(
          0,
          0,
          art.word.width.toDouble(),
          art.word.height.toDouble(),
        ),
        Rect.fromLTWH(484 + (1 - word) * 7, y, 292, height),
        Paint()
          ..filterQuality = FilterQuality.high
          ..color = Colors.white.withValues(alpha: _out(word)),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScmPainter old) =>
      old.art != art ||
      old.clock != clock ||
      old.loading != loading ||
      old.brief != brief ||
      old.loadingEnd != loadingEnd ||
      old.reduced != reduced;
}

class _Artwork {
  _Artwork(this.mark, this.word, this.layers);
  final ui.Image mark, word;
  final List<ui.Image> layers;
  static Future<ui.Image> image(String path) async {
    final bytes = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  static Future<_Artwork> load() async {
    final mark = await image(ScmBrandMark.markAssetPath);
    final word = await image(ScmBrandMark.wordmarkAssetPath);
    final rgba = (await mark.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final layers = await compute(_split, (
      rgba.buffer.asUint8List(),
      mark.width,
      mark.height,
    ));
    final images = <ui.Image>[];
    for (final bytes in layers) {
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        bytes,
        mark.width,
        mark.height,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      images.add(await done.future);
    }
    return _Artwork(mark, word, images);
  }
}

// Same alpha threshold, eight-neighbour components and radial classification
// as scm-intro-v3/source.html. Work runs off the UI isolate once per process.
List<Uint8List> _split((Uint8List, int, int) input) {
  final (rgba, w, h) = input;
  final labels = Int32List(w * h), queue = Uint32List(w * h);
  final parts = <({int id, int count, double radius})>[];
  var label = 0;
  for (var i = 0; i < labels.length; i++) {
    if (labels[i] != 0 || rgba[i * 4 + 3] < 8) continue;
    label++;
    var front = 0, end = 1, sx = 0, sy = 0;
    queue[0] = i;
    labels[i] = label;
    while (front < end) {
      final n = queue[front++], x = n % w, y = n ~/ w;
      sx += x;
      sy += y;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx, yy = y + dy;
          if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
          final next = yy * w + xx;
          if (labels[next] == 0 && rgba[next * 4 + 3] >= 8) {
            labels[next] = label;
            queue[end++] = next;
          }
        }
      }
    }
    if (end > 1000) {
      parts.add((
        id: label,
        count: end,
        radius: math.sqrt(
          math.pow(sx / end - w / 2, 2) + math.pow(sy / end - 550, 2),
        ),
      ));
    }
  }
  if (parts.length != 7) throw StateError('SCM artwork component mismatch');
  parts.sort((a, b) => b.count.compareTo(a.count));
  final core = parts.first.id;
  final rings = parts.skip(1).toList()
    ..sort((a, b) => a.radius.compareTo(b.radius));
  final inner = rings.take(3).map((p) => p.id).toSet();
  final outer = rings.skip(3).map((p) => p.id).toSet();
  final output = List.generate(3, (_) => Uint8List(rgba.length));
  for (var i = 0; i < labels.length; i++) {
    final id = labels[i];
    final group = id == core
        ? 0
        : inner.contains(id)
        ? 1
        : outer.contains(id)
        ? 2
        : -1;
    if (group < 0) continue;
    for (var c = 0; c < 4; c++) {
      output[group][i * 4 + c] = rgba[i * 4 + c];
    }
  }
  return output;
}
