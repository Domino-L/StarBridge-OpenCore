import '../../app/localization/app_strings.dart';
import '../settings/bridge_notification_settings_adapter.dart';
import '../settings/notification_settings_models.dart';

/// Shared content only; delivery and account authorization remain with callers.
({String title, String message}) localNotificationContent(
  AppStrings strings,
  LocalRoomReminder event,
  NotificationPreviewMode previewMode,
) {
  final hidden = previewMode == NotificationPreviewMode.hiddenDetails;
  final full = previewMode == NotificationPreviewMode.fullContent;
  final genericTitle = strings.text(
    hidden
        ? 'settings.notification.local.genericTitle'
        : event.kind == 'direct'
        ? 'settings.notification.local.directTitle'
        : event.kind == 'friend'
        ? 'settings.notification.local.friendTitle'
        : 'settings.notification.local.roomTitle',
  );
  final title =
      event.kind == 'direct' && !hidden && event.senderName?.isNotEmpty == true
      ? strings
            .text('settings.notification.local.directFrom')
            .replaceAll('{sender}', event.senderName!)
      : genericTitle;
  final message = strings
      .text(
        hidden
            ? 'settings.notification.local.hiddenBody'
            : event.kind == 'direct' &&
                  full &&
                  event.messagePreview?.isNotEmpty == true
            ? 'settings.notification.local.directPreview'
            : event.kind != 'room'
            ? 'settings.notification.local.socialBody'
            : full
            ? 'settings.notification.local.fullBody'
            : 'settings.notification.local.sourceBody',
      )
      .replaceAll('{invitations}', '${event.invitations}')
      .replaceAll('{applications}', '${event.applications}')
      .replaceAll('{message}', event.messagePreview ?? '');
  return (title: title, message: message);
}
