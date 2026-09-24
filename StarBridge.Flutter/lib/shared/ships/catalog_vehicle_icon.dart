import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

import 'catalog_vehicle_glyph.dart';
import 'catalog_vehicle_icon_geometry.dart';
import 'catalog_ground_vehicle_icon_geometry.dart';
import 'catalog_vehicle_motion.dart';
import 'catalog_vehicle_motion_data.dart';

/// Approved category artwork. Static unless a caller supplies paint-only motion.
///
/// Categories: combat, exploration, logistics, industrial, support,
/// competition, unclassified. Sizes: small, medium, large, capital;
/// competition has no capital variant. Keys are exact and case-sensitive.
/// The byKey factory also supports the 19 approved ground/MPUV glyphs;
/// provenance is recorded in catalog_ground_vehicle_icon_sources.json.
/// Unsupported combinations reserve [size] without painting a fallback.
/// Intended beside visible category/specification text, so it adds no semantics.
class CatalogVehicleIcon extends StatelessWidget {
  const CatalogVehicleIcon({
    required this.category,
    required this.sizeClass,
    this.size = 28,
    this.motion,
    super.key,
  }) : exactKey = null,
       assert(size >= 0 && size < double.infinity);

  factory CatalogVehicleIcon.byKey({
    required String iconKey,
    double size = 28,
    Listenable? motion,
    Key? key,
  }) {
    final split = iconKey.lastIndexOf('-');
    if (split > 0 &&
        catalogVehicleGlyphs[iconKey.substring(0, split)]?.containsKey(
              iconKey.substring(split + 1),
            ) ==
            true) {
      return CatalogVehicleIcon(
        category: iconKey.substring(0, split),
        sizeClass: iconKey.substring(split + 1),
        size: size,
        motion: motion,
        key: key,
      );
    }
    return CatalogVehicleIcon._exact(
      iconKey: iconKey,
      size: size,
      motion: motion,
      key: key,
    );
  }
  const CatalogVehicleIcon._exact({
    required String iconKey,
    this.size = 28,
    this.motion,
    super.key,
  }) : category = '',
       sizeClass = '',
       exactKey = iconKey,
       assert(size >= 0 && size < double.infinity);

  static bool supportsKey(String key) {
    if (catalogGroundVehicleGlyphs.containsKey(key)) return true;
    final split = key.lastIndexOf('-');
    return split > 0 &&
        catalogVehicleGlyphs[key.substring(0, split)]?.containsKey(
              key.substring(split + 1),
            ) ==
            true;
  }

  /// Null means intentionally static (including the four unclassified glyphs).
  static Duration? motionDuration(String key) {
    final spec = catalogMotions[key];
    return spec == null ? null : Duration(milliseconds: spec.duration);
  }

  final String? exactKey;

  final String category;
  final String sizeClass;
  final double size;
  final Listenable? motion;

  @override
  Widget build(BuildContext context) {
    final dimension = size.isFinite && size >= 0 ? size : 0.0;
    final key = exactKey;
    final split = key?.lastIndexOf('-') ?? -1;
    CatalogVehicleGlyph? glyph;
    if (key == null) {
      glyph = catalogVehicleGlyphs[category]?[sizeClass];
    } else {
      glyph = catalogGroundVehicleGlyphs[key];
      if (glyph == null && split > 0) {
        glyph =
            catalogVehicleGlyphs[key.substring(0, split)]?[key.substring(
              split + 1,
            )];
      }
    }
    return SizedBox.square(
      dimension: dimension,
      child: glyph == null || dimension == 0
          ? null
          : ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _CatalogVehiclePainter(
                    glyph,
                    context.tokens.colors.textPrimary,
                    motion,
                    motion is Animation<double>
                        ? catalogMotions[key ?? '$category-$sizeClass']
                        : null,
                  ),
                ),
              ),
            ),
    );
  }
}

class _CatalogVehiclePainter extends CustomPainter {
  _CatalogVehiclePainter(
    this.glyph,
    this.hull,
    Listenable? motion,
    this.sequence,
  ) : progress = motion is Animation<double> ? motion : null,
      super(repaint: motion);
  final CatalogVehicleGlyph glyph;
  final Color hull;
  final CatalogMotionSpec? sequence;
  final Animation<double>? progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final sequence = this.sequence;
    final progress = this.progress;
    if (sequence != null &&
        progress != null &&
        progress.value * sequence.duration < sequence.staticAt) {
      sequence.data.paint(canvas, size, hull, progress.value);
      return;
    }
    final box = glyph.viewBox;
    final scale = math.min(size.width / box.width, size.height / box.height);
    canvas.save();
    canvas.translate(
      (size.width - box.width * scale) / 2,
      (size.height - box.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-box.left, -box.top);
    canvas.clipRect(box);
    final paint = Paint()..isAntiAlias = true;
    for (var index = 0; index < glyph.layers.length; index++) {
      final layer = glyph.layers[index];
      canvas.save();
      for (final clip in layer.clips) {
        canvas.clipPath(clip);
      }
      paint.color = layer.color ?? hull;
      canvas.drawPath(layer.path, paint);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CatalogVehiclePainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.hull != hull ||
      oldDelegate.sequence != sequence ||
      oldDelegate.progress != progress;
}
