import 'overlay_settings_models.dart';
import 'overlay_settings_port.dart';

final class HostUnavailableOverlaySettingsAdapter
    implements OverlaySettingsPort {
  @override
  Future<OverlaySettingsSnapshot> read() async =>
      const OverlaySettingsSnapshot.unavailable();

  @override
  Future<OverlaySettingsWriteResult> update(
    OverlaySettingsValue settings, {
    required int expectedRevision,
  }) async => const OverlaySettingsWriteResult.failed(
    OverlaySettingsFailure.hostUnavailable,
  );

  @override
  Future<void> close() async {}
}
