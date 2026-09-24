import 'overlay_settings_models.dart';
import 'overlay_settings_port.dart';

final class InMemoryOverlaySettingsAdapter implements OverlaySettingsPort {
  InMemoryOverlaySettingsAdapter({
    OverlaySettingsValue settings = OverlaySettingsValue.defaults,
    this.windowAvailable = false,
  }) : _snapshot = OverlaySettingsSnapshot.available(
         revision: 1,
         settings: settings,
         windowAvailable: windowAvailable,
       );

  final bool windowAvailable;
  OverlaySettingsSnapshot _snapshot;
  OverlaySettingsSnapshot get current => _snapshot;

  @override
  Future<OverlaySettingsSnapshot> read() async => _snapshot;

  @override
  Future<OverlaySettingsWriteResult> update(
    OverlaySettingsValue settings, {
    required int expectedRevision,
  }) async {
    if (_snapshot.revision != expectedRevision) {
      return const OverlaySettingsWriteResult.failed(
        OverlaySettingsFailure.writeConflict,
      );
    }
    _snapshot = OverlaySettingsSnapshot.available(
      revision: expectedRevision + 1,
      settings: settings,
      windowAvailable: windowAvailable,
    );
    return OverlaySettingsWriteResult.completed(_snapshot);
  }

  @override
  Future<void> close() async {}
}
