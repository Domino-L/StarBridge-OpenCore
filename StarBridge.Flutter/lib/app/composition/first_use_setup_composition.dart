import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/onboarding/bridge_onboarding_adapter.dart';
import '../../features/onboarding/bridge_device_review_adapter.dart';
import '../../features/onboarding/bridge_local_statistics_adapter.dart';
import '../../features/onboarding/bridge_local_history_adapter.dart';
import '../../features/onboarding/bridge_native_overlay_observation.dart';
import '../../features/onboarding/bridge_online_review_adapter.dart';
import '../../features/overlay_settings/overlay_appearance_preview_route.dart';
import '../../features/onboarding/device_review_port.dart';
import '../../features/onboarding/onboarding_copy.dart';
import '../../features/onboarding/onboarding_entry.dart';
import '../../features/onboarding/first_use_setup_entry.dart';
import '../../features/overlay_settings/overlay_settings_module.dart';
import '../../features/overlay_settings/overlay_settings_page.dart';
import '../../features/overlay_settings/overlay_settings_feature.dart';
import '../../features/settings/general_settings_page.dart';
import '../../features/settings/notification_settings_page.dart';
import '../../features/settings/notification_settings_module.dart';
import '../../features/settings/notification_editor_frame.dart';
import '../../features/settings/notification_audio_controller.dart';
import '../../features/settings/continuous_play_controller.dart';
import '../../features/settings/continuous_play_dialog.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../feature_registry.dart';
import '../preferences/app_preferences_port.dart';

// Borrow original product editors/owners. Do not create a second preference,
// account-statistics, notification or overlay settings module for this route.
final class FirstUseDeviceEditors {
  const FirstUseDeviceEditors({
    required this.preferences,
    required this.overlay,
    required this.notifications,
    this.playReminder,
    this.audio,
    this.session,
  });
  final AppPreferencesPort preferences;
  final OverlaySettingsModule overlay;
  final NotificationSettingsModule notifications;
  final ContinuousPlayController? playReminder;
  final NotificationAudioController? audio;
  final BridgeClientSession? session;

  Future<void> openNativePreview(BuildContext context) async {
    final workspace = overlay.workspace;
    // Edits save on their own; preview once the last one is written. A save
    // that failed still blocks below, since the preview shows saved values.
    if (workspace != null && workspace.projection.value.dirty) {
      await workspace.save();
      if (!context.mounted) return;
    }
    final projection = workspace?.projection.value;
    final port = workspace?.appearanceLivePort;
    // Use the original, already loaded owner. No refresh that can synchronize
    // a normal runtime, default-preset write, copied module or draft disposal.
    if (workspace == null ||
        projection == null ||
        !projection.available ||
        projection.busy ||
        projection.dirty ||
        port == null) {
      throw StateError('Saved native preview is unavailable.');
    }
    final skin = projection.snapshot?.settings?['skin'];
    if (skin is! String ||
        !projection.snapshot!.appearances.any(
          (appearance) =>
              appearance.id == skin && appearance.isPreviewAvailable,
        )) {
      throw StateError('Saved native preview is unavailable.');
    }
    await showOverlayAppearancePreviewPage(
      context,
      module: workspace,
      port: port,
      appearanceId: skin,
      readOnly: true,
    );
  }

  Future<void> open(BuildContext context, DeviceReviewSection section) async {
    if (section == DeviceReviewSection.playReminder) {
      final reminder = playReminder;
      if (reminder == null) {
        throw StateError('Play reminder editor is unavailable.');
      }
      await showContinuousPlayDialog(context, reminder);
      return;
    }
    final copy = OnboardingCopy(Localizations.localeOf(context));
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: '/first-use/device/${section.name}'),
        builder: (_) => _OriginalDeviceEditor(
          title: copy.text('device.section.${section.name}'),
          confirmLeave: section == DeviceReviewSection.notifications
              ? (_) => confirmNotificationLeave(notifications)
              : section == DeviceReviewSection.overlay
              ? (context) => confirmOverlayWorkspaceLeave(context, overlay)
              : (_) async => true,
          child: switch (section) {
            DeviceReviewSection.application => GeneralSettingsPage(
              preferences: preferences,
            ),
            DeviceReviewSection.overlay => OverlaySettingsPage(module: overlay),
            DeviceReviewSection.notifications => NotificationSettingsPage(
              module: notifications,
              session: session,
              audio: audio,
            ),
            DeviceReviewSection.playReminder => throw StateError(
              'Unreachable reminder page.',
            ),
          },
        ),
      ),
    );
  }
}

class _OriginalDeviceEditor extends StatefulWidget {
  const _OriginalDeviceEditor({
    required this.title,
    required this.child,
    required this.confirmLeave,
  });
  final String title;
  final Widget child;
  final Future<bool> Function(BuildContext) confirmLeave;
  @override
  State<_OriginalDeviceEditor> createState() => _OriginalDeviceEditorState();
}

class _OriginalDeviceEditorState extends State<_OriginalDeviceEditor> {
  bool _leaving = false;
  Future<void> _leave() async {
    if (_leaving) {
      return;
    }
    _leaving = true;
    try {
      if (await widget.confirmLeave(context) && mounted) {
        Navigator.of(context).pop();
      }
    } on Object {
      // An unknown save/leave outcome keeps this original editor open.
    } finally {
      _leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        unawaited(_leave());
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        automaticallyImplyLeading: false,
        leading: BackButton(onPressed: () => unawaited(_leave())),
      ),
      body: widget.child,
    ),
  );
}

/// Product manual continuation is registered only with the complete trusted
/// Host contract. The two subset capabilities alone must not expose this entry
/// or trigger first-use for an existing user. Startup scheduling is separate.
Iterable<FeatureDescriptor> createFirstUseSetupFeatures(
  BridgeClientSession? session,
  FirstUseDeviceEditors editors,
) sync* {
  if (session == null ||
      !session.hostCapabilities.contains(BridgeOnboardingAdapter.capability)) {
    return;
  }
  yield FeatureDescriptor(
    id: 'first-use-setup',
    route: '/settings/setup',
    labelKey: 'settings.firstUse',
    descriptionKey: 'settings.firstUse.description',
    icon: StarBridgeIconSemantic.settings,
    navigationRegion: NavigationRegion.accountMenu,
    navigationParentId: 'settings',
    order: 30,
    buildDestination: (_) =>
        _FirstUseSetupEntry(session: session, editors: editors),
  );
}

class _FirstUseSetupEntry extends StatefulWidget {
  const _FirstUseSetupEntry({required this.session, required this.editors});
  final BridgeClientSession session;
  final FirstUseDeviceEditors editors;
  @override
  State<_FirstUseSetupEntry> createState() => _FirstUseSetupEntryState();
}

class _FirstUseSetupEntryState extends State<_FirstUseSetupEntry> {
  bool _open = false;
  Future<void> _show() async {
    if (_open ||
        !widget.session.hostCapabilities.contains(
          BridgeOnboardingAdapter.capability,
        )) {
      return;
    }
    setState(() {
      _open = true;
    });
    final native = BridgeNativeOverlayObservation(widget.session);
    final history = BridgeLocalHistoryAdapter(widget.session);
    try {
      final primary = FirstUseSetupEntry.of(context);
      if (primary != null) {
        await primary(context);
        return;
      }
      await openFirstUseSetup(
        context,
        BridgeOnboardingAdapter(widget.session),
        appBehavior: widget.editors.preferences,
        skipWelcomeIntro: true,
        deviceReview: BridgeDeviceReviewAdapter(widget.session),
        localStatistics: BridgeLocalStatisticsAdapter(widget.session),
        localHistory: history.supported ? history : null,
        editDeviceSettings: (section) => widget.editors.open(context, section),
        nativeOverlay: native,
        openNativePreview: () => widget.editors.openNativePreview(context),
        onlineReview:
            widget.session.hostCapabilities.contains(
              BridgeOnlineReviewAdapter.capability,
            )
            ? BridgeOnlineReviewAdapter(widget.session)
            : null,
      );
    } finally {
      await native.dispose();
      if (mounted) {
        setState(() {
          _open = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = OnboardingCopy(Localizations.localeOf(context));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.text('entry'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(copy.text('entryBody')),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('first-use-manual-open'),
            onPressed:
                _open ||
                    !widget.session.hostCapabilities.contains(
                      BridgeOnboardingAdapter.capability,
                    )
                ? null
                : _show,
            child: Text(copy.text('keep')),
          ),
        ],
      ),
    );
  }
}
