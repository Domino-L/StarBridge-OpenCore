import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/styles/ship_silhouette_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'ship_silhouette_store.dart';

const shipSilhouetteReveal = Duration(milliseconds: 700);

/// A ship's own silhouette when the optional pack knows it, else [fallback].
/// [names] goes from the most exact identity to the least. Static unless a
/// caller supplies a one-shot [motion]; decorative beside readable ship text.
class ShipVehicleIcon extends StatelessWidget {
  const ShipVehicleIcon({
    required this.names,
    required this.fallback,
    this.size = 28,
    this.motion,
    super.key,
  });

  final List<String?> names;
  final Widget fallback;
  final double size;
  final Animation<double>? motion;

  @override
  Widget build(BuildContext context) => ShipSilhouetteSwitch(
    names: names,
    size: size,
    fallback: fallback,
    builder: (context, ship, grid) =>
        ShipSilhouetteIcon(ship: ship, grid: grid, size: size, motion: motion),
  );
}

/// Keeps the slot empty for the brief pack read so a list never flashes the
/// old artwork before the silhouette.
class ShipSilhouetteSwitch extends StatelessWidget {
  const ShipSilhouetteSwitch({
    required this.names,
    required this.fallback,
    required this.builder,
    this.size = 28,
    super.key,
  });

  final List<String?> names;
  final Widget fallback;
  final double size;
  final Widget Function(BuildContext, ShipSilhouette, double grid) builder;

  @override
  Widget build(BuildContext context) {
    final store = ShipSilhouetteStore.instance..ensureLoaded();
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.load == ShipSilhouetteLoad.pending) {
          return SizedBox.square(dimension: size);
        }
        final pack = store.pack;
        final ship = pack?.find(names);
        return pack == null || ship == null
            ? fallback
            : builder(context, ship, pack.grid);
      },
    );
  }
}

class ShipSilhouetteIcon extends StatelessWidget {
  const ShipSilhouetteIcon({
    required this.ship,
    required this.grid,
    this.size = 28,
    this.motion,
    super.key,
  });

  final ShipSilhouette ship;
  final double grid, size;
  final Animation<double>? motion;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: _ShipSilhouettePainter(
          ship,
          grid,
          context.tokens.isDark
              ? ShipSilhouettePalette.dark
              : ShipSilhouettePalette.light,
          motion,
        ),
      ),
    ),
  );
}

class _ShipSilhouettePainter extends CustomPainter {
  _ShipSilhouettePainter(this.ship, this.grid, this.body, this.motion)
    : super(repaint: motion);

  final ShipSilhouette ship;
  final double grid;
  final List<Color> body;
  final Animation<double>? motion;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.min(size.width, size.height) / grid;
    final progress = motion?.value ?? 1;
    canvas.save();
    canvas.scale(scale);
    // The scan climbs from tail to nose and the body appears behind it.
    final front = grid * (1 - progress.clamp(0.0, 1.0));
    if (progress < 1) {
      canvas.clipRect(Rect.fromLTRB(0, front, grid, grid));
    }
    canvas.drawPath(
      ship.outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.6 / scale
        ..color = ShipSilhouettePalette.halo,
    );
    canvas.drawPath(
      ship.outline,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: body,
        ).createShader(Rect.fromLTWH(0, 0, grid, grid)),
    );
    canvas.drawPath(ship.raised, Paint()..color = ShipSilhouettePalette.raised);
    if (progress < 1) {
      canvas.clipRect(Rect.fromLTRB(0, front, grid, front + grid * .06));
      canvas.drawPath(
        ship.outline,
        Paint()..color = ShipSilhouettePalette.scan,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShipSilhouettePainter oldDelegate) =>
      oldDelegate.ship != ship ||
      oldDelegate.grid != grid ||
      oldDelegate.body != body ||
      oldDelegate.motion != motion;
}
