import 'dart:ui';

/// Exact colors from the accepted vehicle artwork, independent of app theme.
/// Spacecraft and ground variants deliberately have distinct hues.
abstract final class CatalogVehiclePalette {
  static const combat = Color(0xFFFF675C);
  static const exploration = Color(0xFF339CFF);
  static const industrial = Color(0xFFFFD240);
  static const logistics = Color(0xFF39B0C2);
  static const support = Color(0xFF40C977);
  static const competition = Color(0xFFFB6A22);
  static const groundAccent = Color(0xFFA9CE59);
  static const groundExploration = Color(0xFF438EFF);
  static const groundIndustrial = Color(0xFFF2C94C);
  static const groundTransport = Color(0xFF54B9C7);
  static const groundSupport = Color(0xFF42D7A0);
  static const groundCompetition = Color(0xFFFF9C42);
}
