import 'dart:ui';

class CatalogVehicleGlyph {
  const CatalogVehicleGlyph(this.viewBox, this.layers);
  final Rect viewBox;
  final List<CatalogVehicleLayer> layers;
}

class CatalogVehicleLayer {
  const CatalogVehicleLayer(this.path, this.color, this.clips);
  final Path path;
  // Null is the approved white body, adapted to the current theme's foreground.
  // Category accents retain their source colors, without whole-icon tinting.
  final Color? color;
  final List<Path> clips;
}
