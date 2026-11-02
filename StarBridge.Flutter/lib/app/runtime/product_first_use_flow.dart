import 'dart:async';

import 'package:flutter/material.dart';

import '../composition/app_composition.dart';
import '../composition/first_use_setup_composition.dart';
import '../../features/onboarding/bridge_onboarding_adapter.dart';
import '../../features/onboarding/bridge_device_review_adapter.dart';
import '../../features/onboarding/bridge_local_statistics_adapter.dart';
import '../../features/onboarding/bridge_local_history_adapter.dart';
import '../../features/onboarding/bridge_native_overlay_observation.dart';
import '../../features/onboarding/bridge_online_review_adapter.dart';
import '../../features/onboarding/bridge_online_installation_adapter.dart';
import '../../features/onboarding/bridge_onboarding_profile_adapter.dart';
import '../../features/onboarding/bridge_recognition_check_adapter.dart';
import '../../features/onboarding/onboarding_entry.dart';
import 'first_use_onboarding_flow.dart';
import 'startup_prompt_queue.dart';
import 'first_use_recovery_flow.dart';
import '../../features/onboarding/first_use_recovery_dialog.dart';

/// One primary-window route over the already connected composition. Existing
/// device editors, preview and account refresh remain their original owners.
final class ProductFirstUseFlow {
  ProductFirstUseFlow({
    required this.composition,
    required this.queue,
    required this.ready,
    required this.current,
    this.onOwnsDeviceChoices,
  }) {
    final session = composition.firstUseSession;
    if (session == null ||
        !session.hostCapabilities.contains(
          BridgeOnboardingAdapter.capability,
        )) {
      onOwnsDeviceChoices?.call(false);
      return;
    }
    // Until the Host says setup is not needed, setup owns the startup and
    // close choices; the standalone prompts must not ask them first.
    onOwnsDeviceChoices?.call(true);
    _port = BridgeOnboardingAdapter(
      session,
      onGenerationAdvanced: _refreshOwners,
    );
    _recovery = FirstUseRecoveryFlow(
      onHealthy: wake,
      session: session,
      mode: composition.manualPresence?.connectionMode,
      queue: queue,
      ready: () => _current && ready() && !_opening,
      current: () => _current,
      show: (notice) async {
        final context = queue.navigator?.context;
        return context == null ? null : showFirstUseRecovery(context, notice);
      },
      openSetup: () async {
        final context = queue.navigator?.context;
        if (context != null) await open(context);
      },
    );
    _flow = FirstUseOnboardingFlow(
      port: _port!,
      queue: queue,
      ready: () =>
          _current && ready() && queue.navigator?.mounted == true && !_opening,
      isCurrent: () => _current,
      show: () async {
        final context = queue.navigator?.context;
        if (context != null) await open(context);
      },
    );
    _events = session.events
        .where(
          (event) =>
              event.name == 'account.changed' ||
              event.name == 'bootstrap.invalidated' ||
              event.name == 'onboarding.changed',
        )
        .listen((_) => wake());
  }
  final AppComposition composition;
  final StartupPromptQueue queue;
  final bool Function() ready, current;

  /// Reports whether first-use setup will ask startup and close behaviour.
  final ValueChanged<bool>? onOwnsDeviceChoices;
  BridgeOnboardingAdapter? _port;
  FirstUseOnboardingFlow? _flow;
  FirstUseRecoveryFlow? _recovery;
  Future<void>? _checking;
  bool _checkAgain = false;
  StreamSubscription<Object?>? _events;
  bool _disposed = false, _opening = false;
  bool get _current => !_disposed && current();
  bool get supported => _current && _port != null;
  bool get blocksOptionalPrompts =>
      _opening ||
      (_flow?.blocksOptionalPrompts ?? false) ||
      (_recovery?.blocksOptionalPrompts ?? false);
  void wake() {
    if (_current) {
      if (_checking != null) {
        _checkAgain = true;
      } else {
        unawaited(_checking = _check());
      }
      queue.wake();
    }
  }

  Future<void> _check() async {
    try {
      if (_current) {
        final hold = await _recovery?.check() ?? false;
        if (!_current) return;
        if (hold) {
          _flow?.deferAutomaticEntry();
          onOwnsDeviceChoices?.call(true);
        } else {
          await _flow?.check();
          if (_current) {
            onOwnsDeviceChoices?.call(_flow?.lastEligible ?? false);
          }
        }
      }
    } finally {
      _checking = null;
      if (_checkAgain && _current) {
        _checkAgain = false;
        wake();
      }
    }
  }

  Future<void> _refreshOwners() async {
    if (!_current) return;
    await composition.account.refresh();
    if (!_current) return;
    await composition.manualPresence?.connectionMode.refresh();
    if (_current) await composition.manualPresence?.refresh();
  }

  Future<void> open(BuildContext context) async {
    final session = composition.firstUseSession;
    if (!supported || _opening || !context.mounted || session == null) return;
    _opening = true;
    _flow?.consumeManualEntry();
    _recovery?.consumeManualEntry();
    final native = BridgeNativeOverlayObservation(session);
    final history = BridgeLocalHistoryAdapter(session);
    final profile = BridgeOnboardingProfileAdapter(session);
    final editors = FirstUseDeviceEditors(
      preferences: composition.preferences,
      overlay: composition.overlaySettings,
      notifications: composition.notificationSettings,
      playReminder: composition.continuousPlay,
      audio: composition.notificationAudio,
      session: session,
    );
    try {
      await openFirstUseSetup(
        context,
        _port!,
        appBehavior: composition.preferences,
        skipWelcomeIntro: true,
        deviceReview: BridgeDeviceReviewAdapter(session),
        localStatistics: BridgeLocalStatisticsAdapter(session),
        localHistory: history.supported ? history : null,
        nativeOverlay: native,
        onlineReview: BridgeOnlineReviewAdapter(
          session,
          onModeChanged: () async {
            if (_current) {
              await composition.manualPresence?.connectionMode.refresh();
            }
          },
        ),
        onlineInstallation: BridgeOnlineInstallationAdapter(session),
        onOnlineInstalled: _refreshOwners,
        profile: profile,
        recognition: BridgeRecognitionCheckAdapter(session),
        editDeviceSettings: (section) => editors.open(context, section),
        openNativePreview: () => editors.openNativePreview(context),
      );
    } finally {
      try {
        profile.dispose();
        await native.dispose();
      } finally {
        _opening = false;
        if (_current) {
          await _refreshOwners();
          queue.wake();
        }
      }
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_events?.cancel());
    _flow?.dispose();
    _recovery?.dispose();
  }
}
