import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../shared/guide/guide_scope.dart';
import '../../shared/guide/guide_state.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'onboarding_controller.dart';
import 'onboarding_copy.dart';
import 'onboarding_frame.dart';
import 'onboarding_models.dart';
import 'onboarding_step_body.dart';
import 'app_behavior_choice_controller.dart';
import 'device_review_controller.dart';
import 'device_review_port.dart';
import 'local_statistics_controller.dart';
import 'local_history_controller.dart';
import 'native_overlay_check_controller.dart';
import 'online_review_controller.dart';
import 'onboarding_profile_controller.dart';
import 'recognition_check_controller.dart';
import 'recognition_check_panel.dart';

/// Caller owns the controller and the route. This page never creates an account,
/// opens a file, stores a Handle, grants consent, or guesses first-install status.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    required this.controller,
    required this.onClose,
    this.appBehavior,
    this.deviceReview,
    this.editDeviceSettings,
    this.localStatistics,
    this.localHistory,
    this.nativeOverlay,
    this.openNativePreview,
    this.onlineReview,
    this.profile,
    this.recognition,
    super.key,
  });
  final OnboardingController controller;
  final VoidCallback onClose;
  final AppBehaviorChoiceController? appBehavior;
  final DeviceReviewController? deviceReview;
  final Future<void> Function(DeviceReviewSection)? editDeviceSettings;
  final LocalStatisticsController? localStatistics;
  final LocalHistoryController? localHistory;
  final NativeOverlayCheckController? nativeOverlay;
  final Future<void> Function()? openNativePreview;
  final OnlineReviewController? onlineReview;
  final OnboardingProfileController? profile;
  final RecognitionCheckController? recognition;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _closing = false;
  bool _guided = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
    widget.controller.addListener(_activateProfile);
  }

  // The online account is installed by the successful save, so "你的资料"
  // reads only after completion, never during setup.
  void _activateProfile() {
    final view = widget.controller.value;
    // The read-only check polls only while its step is on screen.
    if (view.step == OnboardingStep.verify && !view.completed) {
      widget.recognition?.start();
    } else {
      widget.recognition?.stop();
    }
    if (view.completed && view.mode == OnboardingMode.online) {
      unawaited(widget.profile?.activate());
    }
    // Finishing this setup is what makes a profile a "new user" for the
    // home checklist and automatic tours; old profiles never get them.
    final guide = GuideScope.maybeOf(context)?.controller;
    if (view.completed && !_guided && guide != null) {
      _guided = true;
      // Host installs the profile with this save: re-read it, then record
      // "eligible" for exactly that profile (dropped if the context moves).
      unawaited(
        guide.refresh(
          then: [
            const GuideOp.markEligible(),
            if (widget.recognition?.value.passed ?? false)
              GuideOp.markDone('recognize'),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_activateProfile);
    super.dispose();
  }

  Future<void> _close() async {
    final source = StarBridgeActivationOrigin.sourceOf(context);
    if (_closing ||
        widget.profile?.value.saving == true ||
        widget.controller.value.busy ||
        widget.appBehavior?.value.busy == true ||
        widget.deviceReview?.value.busy == true ||
        widget.localStatistics?.value.busy == true ||
        widget.localHistory?.value.busy == true ||
        widget.nativeOverlay?.value.busy == true ||
        widget.onlineReview?.value.busy == true) {
      return;
    }
    _closing = true;
    try {
      if (widget.controller.value.completed || await widget.controller.save()) {
        if (mounted) widget.onClose();
        return;
      }
      if (!mounted) return;
      final copy = OnboardingCopy(Localizations.localeOf(context));
      final leave = await showStarBridgeDialog<bool>(
        context,
        source: source,
        builder: (context) => AlertDialog(
          title: Text(copy.text('notSaved')),
          content: Text(copy.text('notSavedBody')),
          actions: [
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: false,
              ),
              child: Text(copy.text('keep')),
            ),
            StarBridgeActionButton(
              kind: StarBridgeActionKind.secondary,
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: true,
              ),
              child: Text(copy.text('discard')),
            ),
          ],
        ),
      );
      if (mounted && leave == true) widget.onClose();
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = OnboardingCopy(Localizations.localeOf(context));
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller,
        if (widget.appBehavior != null) widget.appBehavior!,
        if (widget.deviceReview != null) widget.deviceReview!,
        if (widget.localStatistics != null) widget.localStatistics!,
        if (widget.localHistory != null) widget.localHistory!,
        if (widget.nativeOverlay != null) widget.nativeOverlay!,
        if (widget.onlineReview != null) widget.onlineReview!,
        if (widget.profile != null) widget.profile!,
        if (widget.recognition != null) widget.recognition!,
      ]),
      builder: (context, _) {
        final view = widget.controller.value;
        final deviceBusy =
            widget.appBehavior?.value.busy == true ||
            widget.deviceReview?.value.busy == true ||
            widget.localStatistics?.value.busy == true ||
            widget.localHistory?.value.busy == true ||
            widget.nativeOverlay?.value.busy == true ||
            widget.onlineReview?.value.busy == true;
        return PopScope(
          canPop: view.completed,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_close());
          },
          child: RadioGroup<OnboardingMode>(
            groupValue: view.mode,
            onChanged: (mode) {
              if (mode != null && widget.onlineReview?.value.busy != true) {
                widget.controller.chooseMode(mode);
                if (mode == OnboardingMode.online) {
                  unawaited(widget.controller.run(OnboardingAction.applyMode));
                }
              }
            },
            child: OnboardingFrame(
              view: view,
              copy: copy,
              body: OnboardingStepBody(
                controller: widget.controller,
                copy: copy,
                appBehavior: widget.appBehavior,
                deviceReview: widget.deviceReview,
                editDeviceSettings: widget.editDeviceSettings,
                localStatistics: widget.localStatistics,
                localHistory: widget.localHistory,
                nativeOverlay: widget.nativeOverlay,
                openNativePreview: widget.openNativePreview,
                onlineReview: widget.onlineReview,
                profile: widget.profile,
                recognition: widget.recognition,
              ),
              verifyStatus: widget.recognition == null
                  ? null
                  : copy.text(recognitionStatusKey(widget.recognition!.value)),
              nextLabelKey:
                  view.step == OnboardingStep.verify &&
                      widget.recognition?.value.passed != true
                  ? 'skipStep'
                  : null,
              interactionBlocked:
                  deviceBusy || widget.profile?.value.saving == true,
              canGoBack: widget.controller.canGoBack,
              showWelcomeIntro: !widget.controller.skipWelcomeIntro,
              canContinue:
                  !deviceBusy &&
                  widget.controller.canContinue &&
                  (view.step != OnboardingStep.mode ||
                      widget.onlineReview?.value.snapshot.retainsSession !=
                          true) &&
                  (view.step != OnboardingStep.identity ||
                      view.mode != OnboardingMode.online ||
                      widget.onlineReview == null ||
                      !widget.onlineReview!.value.error &&
                          widget
                              .onlineReview!
                              .value
                              .snapshot
                              .identityConfirmed) &&
                  (view.step != OnboardingStep.local ||
                      widget.appBehavior == null ||
                      widget.appBehavior!.value.saved &&
                          !widget.appBehavior!.value.dirty) &&
                  (view.step != OnboardingStep.local ||
                      widget.deviceReview == null ||
                      widget.deviceReview!.value.snapshot.state ==
                          DeviceReviewState.reviewed) &&
                  (view.step != OnboardingStep.local ||
                      widget.localStatistics == null ||
                      (!widget.localStatistics!.value.error &&
                          widget.localStatistics!.value.snapshot.choiceSaved)),
              onNext: () => unawaited(widget.controller.next()),
              onBack: widget.controller.back,
              onClose: () => unawaited(_close()),
            ),
          ),
        );
      },
    );
  }
}
