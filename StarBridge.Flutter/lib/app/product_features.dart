/// Menu workspace is selected explicitly by the build profile.
/// The menu-enabled release and collaborator builds pass this define as true.
/// The Windows runner consumes the same Dart define at configure time.
const menuOverlayEnabled = bool.fromEnvironment(
  'STARBRIDGE_ENABLE_MENU_OVERLAY',
  defaultValue: false,
);
