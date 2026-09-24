import '../../../design_system/styles/catalog_vehicle_palette.dart';
import 'dart:ui';
import '../catalog_vehicle_glyph.dart';

// Generated solely from the 19 ground/MPUV final SVGs in the V1 icon index.
// See catalog_ground_vehicle_icon_sources.json for exact sources and hashes.
// White body = theme foreground (null); source accents and fill rules preserved.
final Map<String, CatalogVehicleGlyph> entries = {
  'ground-exploration-light-rover': CatalogVehicleGlyph(
    const Rect.fromLTWH(0, 0, 40, 40),
    [
      CatalogVehicleLayer(
        (Path()
          ..fillType = PathFillType.evenOdd
          ..moveTo(16, 13)
          ..lineTo(24, 13)
          ..lineTo(27, 17)
          ..lineTo(27, 33)
          ..lineTo(24, 36)
          ..lineTo(16, 36)
          ..lineTo(13, 33)
          ..lineTo(13, 17)
          ..close()
          ..moveTo(17, 17)
          ..lineTo(23, 17)
          ..lineTo(24, 19)
          ..lineTo(24, 23)
          ..lineTo(16, 23)
          ..lineTo(16, 19)
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
          ..moveTo(8, 17)
          ..lineTo(10, 17)
          ..lineTo(11, 18)
          ..lineTo(11, 23)
          ..lineTo(10, 24)
          ..lineTo(8, 24)
          ..lineTo(7, 23)
          ..lineTo(7, 18)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(30, 17)
          ..lineTo(32, 17)
          ..lineTo(33, 18)
          ..lineTo(33, 23)
          ..lineTo(32, 24)
          ..lineTo(30, 24)
          ..lineTo(29, 23)
          ..lineTo(29, 18)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(8, 28)
          ..lineTo(10, 28)
          ..lineTo(11, 29)
          ..lineTo(11, 35)
          ..lineTo(10, 36)
          ..lineTo(8, 36)
          ..lineTo(7, 35)
          ..lineTo(7, 29)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(30, 28)
          ..lineTo(32, 28)
          ..lineTo(33, 29)
          ..lineTo(33, 35)
          ..lineTo(32, 36)
          ..lineTo(30, 36)
          ..lineTo(29, 35)
          ..lineTo(29, 29)
          ..close()),
        CatalogVehiclePalette.groundAccent,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(18.5, 28.5)
          ..lineTo(21.5, 28.5)
          ..lineTo(21.5, 30.5)
          ..lineTo(18.5, 30.5)
          ..close()),
        CatalogVehiclePalette.groundExploration,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(10, 6)
          ..lineTo(15, 1)
          ..lineTo(25, 1)
          ..lineTo(30, 6)
          ..lineTo(28, 7)
          ..lineTo(24, 3)
          ..lineTo(16, 3)
          ..lineTo(12, 7)
          ..close()),
        CatalogVehiclePalette.groundExploration,
        [],
      ),
      CatalogVehicleLayer(
        (Path()
          ..moveTo(20, 5)
          ..lineTo(20.8, 7.2)
          ..lineTo(23, 8)
          ..lineTo(20.8, 8.8)
          ..lineTo(20, 11)
          ..lineTo(19.2, 8.8)
          ..lineTo(17, 8)
          ..lineTo(19.2, 7.2)
          ..close()),
        CatalogVehiclePalette.groundExploration,
        [],
      ),
    ],
  ),
};
