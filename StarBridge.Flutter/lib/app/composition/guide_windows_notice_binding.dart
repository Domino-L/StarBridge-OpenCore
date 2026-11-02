import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../features/settings/desktop_notification_test_button.dart';
import '../../features/settings/notification_settings_models.dart';
import '../../features/settings/notification_settings_module.dart';
import '../../platform/host/desktop_notification_port.dart';
import '../../shared/guide/guide_windows_notice.dart';

/// The guide's view of the Settings "Windows desktop notifications" switch.
/// Turning it on goes through the same save as the Settings toggle.
final class GuideWindowsNoticeBinding implements GuideWindowsNoticePort {
  GuideWindowsNoticeBinding(this._settings, this._desktop) {
    _settings.projection.addListener(_follow);
    _follow();
  }

  final NotificationSettingsModule _settings;
  final DesktopNotificationPort? _desktop;
  final _state = ValueNotifier(GuideWindowsNoticeState.loading);

  @override
  ValueListenable<GuideWindowsNoticeState> get state => _state;

  void _follow() {
    final projection = _settings.projection.value;
    final settings = projection.settings;
    _state.value = switch (projection.availability) {
      NotificationSettingsAvailability.loading =>
        GuideWindowsNoticeState.loading,
      NotificationSettingsAvailability.available
          when settings != null && settings.desktopDeliveryAvailable =>
        settings.channels.windowsDesktopEnabled
            ? GuideWindowsNoticeState.on
            : GuideWindowsNoticeState.off,
      _ => GuideWindowsNoticeState.unavailable,
    };
  }

  @override
  Future<bool> enable() async {
    final projection = _settings.projection.value;
    final settings = projection.settings;
    if (!projection.canEdit ||
        settings == null ||
        !settings.desktopDeliveryAvailable) {
      return false;
    }
    if (settings.channels.windowsDesktopEnabled) return true;
    return _settings.save(
      settings.copyWith(
        channels: settings.channels.copyWith(windowsDesktopEnabled: true),
      ),
    );
  }

  @override
  Widget testButton() {
    final desktop = _desktop;
    if (desktop == null) return const SizedBox.shrink();
    return DesktopNotificationTestButton(port: desktop, enabled: true);
  }

  void dispose() {
    _settings.projection.removeListener(_follow);
    _state.dispose();
  }
}
