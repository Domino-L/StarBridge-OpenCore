import 'dart:math' as math;
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';
import 'dart:ui';

/// Frozen vector sequences exported by Chromium from the approved controllers.
/// Runtime work is a binary search + native Canvas paint. No SVG/JS interpreter,
/// file reads, raster frames, per-tick widget rebuilds or unbounded caches.
class CatalogMotionSpec {
  CatalogMotionSpec(
    this.duration,
    this.staticAt,
    this.frameCount,
    this.viewBox,
    this.createPaths,
    this.layouts,
    this.encoded,
  );

  final int duration, staticAt, frameCount;
  final Rect viewBox;
  final List<Path> Function() createPaths;
  // [0] = opacity group; [1] = end group;
  // [2, path, argb-or-0-for-body, clip-path...] = native path.
  final List<List<List<int>>> layouts;
  final String encoded;
  late final CatalogMotionData data = CatalogMotionData(this);
}

class CatalogMotionData {
  CatalogMotionData(this.spec)
    : bytes = Uint8List.fromList(gzip.decode(base64Decode(spec.encoded))).buffer
          .asByteData(),
      paths = spec.createPaths() {
    final counts = spec.layouts
        .map(
          (layout) => layout.fold<int>(
            0,
            (sum, op) =>
                sum +
                (op[0] == 0
                    ? 1
                    : op[0] == 1
                    ? 0
                    : 7 + (op.length - 3) * 6),
          ),
        )
        .toList();
    var offset = 0;
    for (var i = 0; i < spec.frameCount; i++) {
      times.add(bytes.getFloat32(offset, Endian.little));
      final layout = bytes.getUint16(offset + 4, Endian.little);
      layoutIds.add(layout);
      offsets.add(offset + 6);
      offset += 6 + (counts[layout] + 4) * 4;
    }
    assert(offset == bytes.lengthInBytes);
  }

  final CatalogMotionSpec spec;
  final ByteData bytes;
  final List<Path> paths;
  final List<double> times = [];
  final List<int> offsets = [], layoutIds = [];
  final Float64List _matrix = Float64List(16)
    ..[10] = 1
    ..[15] = 1;
  final Float64List _shapeMatrix = Float64List(16);
  final Paint _paint = Paint()..isAntiAlias = true;

  void paint(Canvas canvas, Size size, Color hull, double progress) {
    final time = progress.clamp(0.0, 1.0) * spec.duration;
    var low = 0, high = times.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (times[mid] <= time) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    final next = math.min(low + 1, times.length - 1);
    final span = times[next] - times[low];
    // Never interpolate across a controller's DOM topology/paint-order change.
    final blend = layoutIds[low] == layoutIds[next] && span > 0
        ? ((time - times[low]) / span).clamp(0.0, 1.0)
        : 0.0;
    var a = offsets[low], b = offsets[next];
    double take() {
      final from = bytes.getFloat32(a, Endian.little);
      final to = blend == 0 ? from : bytes.getFloat32(b, Endian.little);
      a += 4;
      b += 4;
      return from + (to - from) * blend;
    }

    void matrix() {
      _matrix[0] = take();
      _matrix[1] = take();
      _matrix[4] = take();
      _matrix[5] = take();
      _matrix[12] = take();
      _matrix[13] = take();
    }

    final view = spec.viewBox;
    final scale = math.min(size.width / view.width, size.height / view.height);
    canvas.save();
    canvas.translate(
      (size.width - view.width * scale) / 2,
      (size.height - view.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-view.left, -view.top);
    // Match the existing static viewport at rest; expand only as far as actual
    // moving geometry requires (cargo/beam/tails must not be cut off).
    canvas.clipRect(Rect.fromLTRB(take(), take(), take(), take()));
    // Effects such as MPUV cargo extend beyond the final silhouette. Keep them,
    // but bound opacity layers to a tiny icon-sized surface (never the window).
    final bounds = view.inflate(view.longestSide);
    final hidden = <bool>[];
    var invisible = false;
    for (final op in spec.layouts[layoutIds[low]]) {
      if (op[0] == 0) {
        final alpha = take().clamp(0.0, 1.0);
        hidden.add(invisible);
        invisible = invisible || alpha == 0;
        if (!invisible && alpha < 1) {
          canvas.saveLayer(
            bounds,
            Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
          );
        } else {
          canvas.save();
        }
      } else if (op[0] == 1) {
        canvas.restore();
        invisible = hidden.removeLast();
      } else {
        final alpha = take().clamp(0.0, 1.0);
        matrix();
        // Source clips are fixed in their own ancestors' coordinates, not in
        // the moving projectile/tool coordinates. Transform paths independently.
        _shapeMatrix.setAll(0, _matrix);
        canvas.save();
        for (final clip in op.skip(3)) {
          matrix();
          if (!invisible && alpha > 0) {
            canvas.clipPath(paths[clip].transform(_matrix));
          }
        }
        if (!invisible && alpha > 0) {
          canvas.transform(_shapeMatrix);
          final color = op[2] == 0 ? hull : Color(op[2]);
          _paint.color = color.withValues(alpha: color.a * alpha);
          canvas.drawPath(paths[op[1]], _paint);
        }
        canvas.restore();
      }
    }
    canvas.restore();
  }
}
