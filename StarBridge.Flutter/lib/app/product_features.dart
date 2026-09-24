/// Unreleased menu workspace is opt-in for development acceptance only.
/// The Windows runner consumes the same Dart define at configure time.
const menuOverlayEnabled = bool.fromEnvironment(
  'STARBRIDGE_ENABLE_MENU_OVERLAY',
  defaultValue: false,
);
