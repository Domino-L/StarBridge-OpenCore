import 'notification_settings_models.dart';
import 'notification_settings_port.dart';

final class HostUnavailableNotificationSettingsAdapter
    implements NotificationSettingsPort {
  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<NotificationSettingsSnapshot> read() async =>
      const NotificationSettingsSnapshot.unavailable();

  @override
  Future<NotificationSettingsWriteResult> update(
    NotificationSettingsValue settings, {
    required int expectedRevision,
  }) async => const NotificationSettingsWriteResult.failed(
    NotificationSettingsFailure.hostUnavailable,
  );

  @override
  Future<void> close() async {}
}
