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
  final pages = lifetime.toolPages;
  void hudSettings() => navigation.value = OpenDestinationIntent('/overlay');
  // The main fleet and organization pages, from "do this in the client".
  void requested() {
    final (route, _) = pages.requested.value ?? ('', 0);
    if (route == '/fleet' || route == '/communities') {
      navigation.value = OpenDestinationIntent(route);
    }
  }

  pages.hudSettings.addListener(hudSettings);
  pages.requested.addListener(requested);
  return () {
    pages.hudSettings.removeListener(hudSettings);
    pages.requested.removeListener(requested);
  };
}
