import 'package:flutter/foundation.dart';

import 'notification_settings_models.dart';

Object playerActivityKey(PlayerActivityNotificationSettings v) => (
  v.enabled,
  v.includeOfficialFleet,
  v.includeFriends,
  v.includeCurrentRoom,
  v.notifyOnline,
  v.notifyOffline,
  v.notifyGameStarted,
  v.notifyGameStopped,
  v.backgroundOnly,
  v.reduceInGame,
);

bool sameNotificationSettings(
  NotificationSettingsValue a,
  NotificationSettingsValue b,
) {
  Object key(NotificationSettingsValue v) => (
    v.channels.inAppEnabled,
    v.channels.windowsDesktopEnabled,
    v.channels.directMessageWindowsEnabled,
    v.channels.overlayEnabled,
    v.channels.desktopPosition,
    v.channels.sound.enabled,
    v.previewMode,
    playerActivityKey(v.playerActivity),
    v.continuousPlay.enabled,
    v.continuousPlay.firstReminderMinutes,
    v.continuousPlay.repeatReminderMinutes,
  );
  return key(a) == key(b) &&
      listEquals(
        [for (final r in a.sourceRules) (r.sourceRef, r.mode)],
        [for (final r in b.sourceRules) (r.sourceRef, r.mode)],
      );
}
