import 'package:flutter/foundation.dart';

import '../../platform/window/method_channel_menu_window_lifetime.dart';
import '../routing/open_destination_intent.dart';

/// Forwards the menu's fixed client-page intents to shell navigation. Each
/// request is a fresh intent, so asking twice navigates twice. The caller
/// unbinds in dispose, before the navigation notifier can go away.
VoidCallback bindMenuToolPages(
  MenuWindowLifetime lifetime,
  ValueNotifier<OpenDestinationIntent?> navigation,
) {
  void hudSettings() => navigation.value = OpenDestinationIntent('/overlay');
  lifetime.toolPages.hudSettings.addListener(hudSettings);
  return () => lifetime.toolPages.hudSettings.removeListener(hudSettings);
}
