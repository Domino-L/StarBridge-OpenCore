import '../../../design_system/styles/catalog_vehicle_palette.dart';
import 'dart:ui';
import '../catalog_vehicle_glyph.dart';

// Generated solely from the 19 ground/MPUV final SVGs in the V1 icon index.
// See catalog_ground_vehicle_icon_sources.json for exact sources and hashes.
// White body = theme foreground (null); source accents and fill rules preserved.
final Map<String, CatalogVehicleGlyph> entries = {
  'ground-competition-gravlev': CatalogVehicleGlyph(
    const Rect.fromLTWH(0, 0, 40, 40),
    [
      CatalogVehicleLayer(
        (Path()
          ..fillType = PathFillType.evenOdd
          ..moveTo(20, 3)
          ..cubicTo(21.5, 7.1, 23.2, 10.6, 23.7, 15)
          ..lineTo(23.5, 21)
          ..lineTo(21.5, 24)
          ..lineTo(18.5, 24)
          ..lineTo(16.5, 21)
          ..lineTo(16.3, 15)
          ..cubicTo(16.8, 10.6, 18.5, 7.1, 20, 3)
          ..close()
          ..moveTo(20, 10)
          ..lineTo(21.2, 13)
          ..lineTo(21.2, 19)
          ..lineTo(18.8, 19)
          ..lineTo(18.8, 13)
          ..close()),
        null,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(18.5, 26)
          ..lineTo(21.5, 26)
          ..lineTo(23.5, 28)
          ..lineTo(23.5, 31)
          ..lineTo(21.5, 33)
          ..lineTo(18.5, 33)
          ..lineTo(16.5, 31)
          ..lineTo(16.5, 28)
          ..close()),
        null,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(14, 7)
          ..cubicTo(12.8, 10.1, 10.2, 13.6, 9.7, 17.5)
          ..lineTo(9.2, 23)
          ..lineTo(13.9, 23)
          ..lineTo(14.4, 17.8)
          ..cubicTo(14.7, 13.5, 14.7, 9.8, 14, 7)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(26, 7)
          ..cubicTo(27.2, 10.1, 29.8, 13.6, 30.3, 17.5)
          ..lineTo(30.8, 23)
          ..lineTo(26.1, 23)
          ..lineTo(25.6, 17.8)
          ..cubicTo(25.3, 13.5, 25.3, 9.8, 26, 7)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(9, 25)
          ..lineTo(13.8, 25)
          ..lineTo(13.3, 30.8)
          ..lineTo(11.4, 34)
          ..lineTo(9, 34)
          ..lineTo(8.8, 30.5)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(26.2, 25)
          ..lineTo(31, 25)
          ..lineTo(31.2, 30.5)
          ..lineTo(31, 34)
          ..lineTo(28.6, 34)
          ..lineTo(26.7, 30.8)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(18.5, 33)
          ..lineTo(21.5, 33)
          ..lineTo(20, 36)
          ..close()),
        CatalogVehiclePalette.groundCompetition,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(17, 38)
          ..lineTo(23, 38)
          ..lineTo(22, 40)
          ..lineTo(18, 40)
          ..close()),
        CatalogVehiclePalette.groundCompetition,
        [],
      ),
    ],
  ),
};
