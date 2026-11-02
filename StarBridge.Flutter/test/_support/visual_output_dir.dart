import 'dart:io';

/// Resolves visual artifacts without changing legacy unconfigured locations.
/// The process environment takes precedence over the same Dart define.
String visualOutputDir(String batch, {String legacySubdirectory = 'visual'}) {
  final environment = Platform.environment['STARBRIDGE_TEST_VISUAL_DIR'];
  const define = String.fromEnvironment('STARBRIDGE_TEST_VISUAL_DIR');
  final root = environment != null && environment.isNotEmpty
      ? environment
      : define;
  if (root.isNotEmpty) {
    return '$root/$batch/visual';
  }
  final legacy = '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path}/Documents/SC Fleet Command/work/$batch';
  return legacySubdirectory.isEmpty ? legacy : '$legacy/$legacySubdirectory';
}
