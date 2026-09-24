import '../../localization/app_strings.dart';
import 'shell_chrome_projection.dart';

String gamePresenceLabel(AppStrings strings, ShellChromeProjection projection) {
  final base = strings.text(projection.gamePresenceKey);
  final version = projection.gameVersion;
  return projection.gamePresence == GamePresenceState.running && version != null
      ? '$base · $version'
      : base;
}

String displayPresenceLabel(
  AppStrings strings,
  ShellChromeProjection projection,
) {
  return projection.displayPresenceKey == 'presence.inGame'
      ? gamePresenceLabel(strings, projection)
      : strings.text(projection.displayPresenceKey);
}
