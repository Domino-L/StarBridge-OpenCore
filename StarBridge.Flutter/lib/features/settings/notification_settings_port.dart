import 'notification_settings_models.dart';

abstract interface class NotificationSettingsPort {
  Stream<void> get invalidations;

  Future<NotificationSettingsSnapshot> read();

  Future<NotificationSettingsWriteResult> update(
    NotificationSettingsValue settings, {
    required int expectedRevision,
  });

  Future<void> close();
}
