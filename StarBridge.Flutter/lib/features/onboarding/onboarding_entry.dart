import 'package:flutter/material.dart';

import '../../app/preferences/app_preferences_port.dart';
import 'app_behavior_choice_controller.dart';
import 'onboarding_controller.dart';
import 'onboarding_page.dart';
import 'onboarding_port.dart';
import 'device_review_controller.dart';
import 'device_review_port.dart';
import 'local_statistics_port.dart';
import 'local_statistics_controller.dart';
import 'local_history_port.dart';
import 'local_history_controller.dart';
import 'native_overlay_observation.dart';
import 'native_overlay_check_controller.dart';
import 'online_review_port.dart';
import 'online_review_controller.dart';
import 'online_installation_port.dart';
import 'onboarding_profile_controller.dart';
import 'onboarding_profile_port.dart';
import 'recognition_check_controller.dart';
import 'recognition_check_port.dart';

/// Manual or StartupPromptQueue entry. The caller must supply a real Adapter.
/// There is deliberately no demo Adapter or installation guess in this route.
Future<void> openFirstUseSetup(
  BuildContext context,
  OnboardingPort port, {
  AppPreferencesPort? appBehavior,
  DeviceReviewPort? deviceReview,
  LocalStatisticsPort? localStatistics,
  LocalHistoryPort? localHistory,
  Future<void> Function(DeviceReviewSection)? editDeviceSettings,
  NativeOverlayObservationPort? nativeOverlay,
  Future<void> Function()? openNativePreview,
  OnlineReviewPort? onlineReview,
  OnlineInstallationPort? onlineInstallation,
  Future<void> Function()? onOnlineInstalled,
  OnboardingProfilePort? profile,
  RecognitionCheckPort? recognition,
  bool skipWelcomeIntro = false,
}) async {
  final controller = OnboardingController(
    port,
    skipWelcomeIntro: skipWelcomeIntro,
  );
  final behavior = appBehavior == null
      ? null
      : AppBehaviorChoiceController(appBehavior);
  final device = deviceReview == null
      ? null
      : DeviceReviewController(deviceReview);
  final statistics = localStatistics == null
      ? null
      : LocalStatisticsController(localStatistics);
  final history = localHistory == null
      ? null
      : LocalHistoryController(localHistory);
  final native = nativeOverlay == null
      ? null
      : NativeOverlayCheckController(nativeOverlay);
  final online = onlineReview == null
      ? null
      : OnlineReviewController(
          onlineReview,
          installation: onlineInstallation,
          onInstalled: onOnlineInstalled,
        );
  final check = recognition == null
      ? null
      : RecognitionCheckController(recognition);
  final ownProfile = profile == null
      ? null
      : OnboardingProfileController(profile);
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/first-use'),
        builder: (routeContext) => OnboardingPage(
          controller: controller,
          appBehavior: behavior,
          deviceReview: device,
          localStatistics: statistics,
          localHistory: history,
          editDeviceSettings: editDeviceSettings,
          nativeOverlay: native,
          openNativePreview: openNativePreview,
          onlineReview: online,
          profile: ownProfile,
          recognition: check,
          onClose: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  } finally {
    controller.dispose();
    behavior?.dispose();
    device?.dispose();
    statistics?.dispose();
    history?.dispose();
    native?.dispose();
    online?.dispose();
    ownProfile?.dispose();
    check?.dispose();
  }
}
