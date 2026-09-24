import 'overlay_settings_models.dart';

abstract interface class OverlaySettingsPort {
  Future<OverlaySettingsSnapshot> read();

  Future<OverlaySettingsWriteResult> update(
    OverlaySettingsValue settings, {
    required int expectedRevision,
  });

  Future<void> close();
}
