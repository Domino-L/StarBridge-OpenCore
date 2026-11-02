/// One compiled product scope, not a preference, session or permission owner.
/// Official candidates must set this define and verify it in their build receipt.
/// The interaction suites, first-use guide and connection modes ship in both
/// official and development builds.
abstract final class OfficialClientProfile {
  static const enabled = bool.fromEnvironment('STARBRIDGE_OFFICIAL_CLIENT');
  static const advancedInteractions = true;
  static const firstUseGuide = true;
  static const connectionModes = true;
  static const newOfflineSelection = connectionModes;
}
