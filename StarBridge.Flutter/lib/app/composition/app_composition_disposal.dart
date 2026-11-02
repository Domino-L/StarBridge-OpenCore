import '../../features/official_fleet/bridge_official_fleet_shared_ships.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_composition.dart';

/// Keep the original synchronous teardown order. The borrowed Bridge lifetime
/// ends only after all primary and independent-window image IO actually exits.
void disposeAppComposition(
  AppComposition composition, {
  required VoidCallback releaseAccountShellChrome,
  VoidCallback? releaseSharingStatus,
  Future<void> Function()? closeNativeHost,
}) {
  composition.remoteImageOwner.dispose();
  composition.imageMaintenance.dispose();
  final mediaExit = composition.remoteImages.retireAsync();
  composition.remoteImages.dispose();
  composition.handleMismatch.dispose();
  releaseSharingStatus?.call();
  unawaited(composition.userInteractions?.close());
  composition.directMessageRequests?.dispose();
  composition.tradeChat?.dispose();
  composition.tradeChatPort?.dispose();
  composition.directMessageRefresh?.dispose();
  composition.friendRequestRefresh?.dispose();
  composition.socialActivity?.dispose();
  composition.manualPresence?.dispose();
  releaseAccountShellChrome();
  composition.appActivity.dispose();
  composition.gamePresence?.dispose();
  composition.gameplayTime?.dispose();
  composition.gameLog?.dispose();
  composition.features.dispose();
  composition.account.dispose();
  composition.personalProfile.dispose();
  composition.officialFleet.dispose();
  unawaited(composition.officialFleetHangarSharingPort?.close());
  final sharedShips = composition.officialFleetSharedShipsPort;
  if (sharedShips is BridgeOfficialFleetSharedShips) {
    unawaited(sharedShips.close());
  }
  composition.partyRooms.dispose();
  composition.communities.dispose();
  composition.friends.dispose();
  composition.syncPrivacy.dispose();
  composition.socialPrivacy?.dispose();
  composition.localPrivacy?.dispose();
  composition.notificationSettings.dispose();
  composition.notificationInbox.dispose();
  composition.applicationSupport.dispose();
  composition.notificationAudio?.dispose();
  composition.continuousPlay?.dispose();
  composition.overlaySettings.dispose();
  if (composition.ownsPreferences) composition.preferences.dispose();
  if (closeNativeHost != null) {
    unawaited(() async {
      await mediaExit;
      await closeNativeHost();
    }());
  }
}
