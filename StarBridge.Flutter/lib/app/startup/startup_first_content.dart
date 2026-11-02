import 'package:flutter/foundation.dart';

import '../../features/account/account_module.dart';
import '../../features/settings/local_privacy_controller.dart';
import '../composition/app_composition.dart';
import '../runtime/sharing_status_monitor.dart';

/// One item the user sees at a glance when the shell first appears. It is
/// settled once it shows real data, an empty result or a failure; loading and
/// placeholder states keep the startup screen up. Nothing here starts a read:
/// the shell, built offstage behind the startup screen, starts its own reads.
final class StartupFirstContentItem {
  const StartupFirstContentItem(this.name, this.listenable, this.settled);
  final String name;
  final Listenable listenable;
  final bool Function() settled;
}

/// Bounded so a stalled read can never keep the user on the startup screen.
abstract final class StartupFirstContentLimit {
  static const safety = Duration(seconds: 20);
}

List<StartupFirstContentItem> startupFirstContent(AppComposition c) => [
  StartupFirstContentItem(
    'callSign',
    c.account.projection,
    () => c.account.presentationSettled,
  ),
  StartupFirstContentItem(
    'joinedCommunities',
    c.communities,
    () => c.communities.joinedLoaded || c.communities.joinedError != null,
  ),
  if (c.manualPresence?.source.controller case final presence?)
    StartupFirstContentItem(
      'presence',
      presence,
      () =>
          presence.isOffline ||
          presence.failed ||
          presence.selfKey != 'presence.unknown',
    ),
  if (c.sharingStatus case final sharing?)
    StartupFirstContentItem(
      'sharing',
      Listenable.merge([sharing, sharing.controller]),
      () => sharingSettled(sharing),
    ),
];

@visibleForTesting
bool sharingSettled(SharingStatusMonitor sharing) {
  final controller = sharing.controller;
  if (sharing.isOffline || sharing.indicator != SharingIndicatorState.unknown) {
    return true;
  }
  return switch (controller.status) {
    LocalPrivacyStatus.unavailable || LocalPrivacyStatus.signedOut => true,
    LocalPrivacyStatus.ready =>
      // Never configured: "unconfirmed" is the real, final state.
      !controller.hasSaved || controller.publicationReadFailures > 0,
    _ => false,
  };
}
