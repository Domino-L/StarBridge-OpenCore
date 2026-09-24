import '../../../design_system/styles/catalog_vehicle_palette.dart';
import 'dart:ui';
import '../catalog_vehicle_glyph.dart';

// Generated solely from the 19 ground/MPUV final SVGs in the V1 icon index.
// See catalog_ground_vehicle_icon_sources.json for exact sources and hashes.
// White body = theme foreground (null); source accents and fill rules preserved.
final Map<String, CatalogVehicleGlyph> entries = {
  'ground-competition-light-rover': CatalogVehicleGlyph(
    const Rect.fromLTWH(0, 0, 40, 40),
    [
      CatalogVehicleLayer(
        (Path()
          ..fillType = PathFillType.evenOdd
          ..moveTo(20, 5)
          ..cubicTo(22, 7.2, 24.2, 10, 25, 14)
          ..lineTo(26, 20)
          ..lineTo(25, 25)
          ..lineTo(26, 32)
          ..lineTo(23, 35)
          ..lineTo(17, 35)
          ..lineTo(14, 32)
          ..lineTo(15, 25)
          ..lineTo(14, 20)
          ..lineTo(15, 14)
          ..cubicTo(15.8, 10, 18, 7.2, 20, 5)
          ..close()
          ..moveTo(20, 12)
          ..cubicTo(21.3, 13.6, 22.6, 16, 23, 19)
          ..lineTo(23, 23)
          ..lineTo(17, 23)
          ..lineTo(17, 19)
          ..cubicTo(17.4, 16, 18.7, 13.6, 20, 12)
          ..close()
          ..moveTo(17, 27)
          ..lineTo(23, 27)
          ..lineTo(23, 32)
          ..lineTo(17, 32)
          ..close()),
        null,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(9, 13)
          ..lineTo(11, 13)
          ..lineTo(12, 14)
          ..lineTo(12, 20)
          ..lineTo(11, 21)
          ..lineTo(9, 21)
          ..lineTo(8, 20)
          ..lineTo(8, 14)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(29, 13)
          ..lineTo(31, 13)
          ..lineTo(32, 14)
          ..lineTo(32, 20)
          ..lineTo(31, 21)
          ..lineTo(29, 21)
          ..lineTo(28, 20)
          ..lineTo(28, 14)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(7, 27)
          ..lineTo(11, 27)
          ..lineTo(12, 28)
          ..lineTo(12, 34)
          ..lineTo(11, 35)
          ..lineTo(7, 35)
          ..lineTo(6, 34)
          ..lineTo(6, 28)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(29, 27)
          ..lineTo(33, 27)
          ..lineTo(34, 28)
          ..lineTo(34, 34)
          ..lineTo(33, 35)
          ..lineTo(29, 35)
          ..lineTo(28, 34)
          ..lineTo(28, 28)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(18, 28)
          ..lineTo(22, 28)
          ..lineTo(21, 31)
          ..lineTo(19, 31)
          ..close()),
        CatalogVehiclePalette.groundCompetition,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(17, 37)
          ..lineTo(23, 37)
          ..lineTo(22, 39)
          ..lineTo(18, 39)
          ..close()),
        CatalogVehiclePalette.groundCompetition,
        [],
      ),
    ],
  ),
};
