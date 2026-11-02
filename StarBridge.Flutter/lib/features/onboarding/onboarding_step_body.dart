import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';

import 'package:flutter/material.dart';

import '../../app/runtime/test_build_notice_copy.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'onboarding_controller.dart';
import 'onboarding_copy.dart';
import 'onboarding_models.dart';
import 'app_behavior_choice_controller.dart';
import 'app_behavior_choice_panel.dart';
import 'device_review_controller.dart';
import 'device_review_panel.dart';
import 'device_review_port.dart';
import 'local_statistics_controller.dart';
import 'local_statistics_panel.dart';
import 'local_history_controller.dart';
import 'local_history_panel.dart';
import 'onboarding_summary.dart';
import 'native_overlay_check_controller.dart';
import 'native_overlay_check_panel.dart';
import 'online_review_controller.dart';
import 'online_review_panel.dart';
import 'onboarding_profile_controller.dart';
import 'onboarding_profile_panel.dart';
import 'recognition_check_controller.dart';
import 'recognition_check_panel.dart';

class OnboardingStepBody extends StatelessWidget {
  const OnboardingStepBody({
    required this.controller,
    required this.copy,
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
  final OnboardingCopy copy;
  final AppBehaviorChoiceController? appBehavior;
  final DeviceReviewController? deviceReview;
  final Future<void> Function(DeviceReviewSection)? editDeviceSettings;
  final LocalStatisticsController? localStatistics;
  final LocalHistoryController? localHistory;
  final NativeOverlayCheckController? nativeOverlay;
  final Future<void> Function()? openNativePreview;
  final OnlineReviewController? onlineReview;

  /// "你的资料" after an online setup was saved; never shown before that.
  final OnboardingProfileController? profile;

  /// Optional, skippable "确认识别正常" check.
  final RecognitionCheckController? recognition;
  OnboardingView get view => controller.value;

  Widget _action(String label, OnboardingAction action) =>
      StarBridgeActionButton(
        controlKey: Key('onboarding-action-${action.name}'),
        kind: StarBridgeActionKind.secondary,
        onActivate: _tap(
          view.busy || onlineReview?.value.busy == true || !view.facts.available
              ? null
              : () => controller.run(action),
        ),
        child: Text(copy.text(label)),
      );

  Widget _refresh() => StarBridgeActionButton(
    controlKey: const Key('onboarding-refresh'),
    kind: StarBridgeActionKind.quiet,
    onActivate: _tap(
      view.busy || onlineReview?.value.busy == true
          ? null
          : view.step == OnboardingStep.identity
          ? controller.checkEvidence
          : controller.refresh,
    ),
    child: Text(copy.text('retry')),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final f = view.facts;
    final content = switch (view.step) {
      OnboardingStep.welcome => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Text(testBuildNoticeBody(copy.locale))],
      ),
      OnboardingStep.mode => _mode(context),
      OnboardingStep.log => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fact(context, 'version', f.version ?? copy.text('unknown')),
          SizedBox(height: t.space.md),
          Text(copy.text(f.logReady ? 'logReady' : 'notChecked')),
          SizedBox(height: t.space.lg),
          Wrap(
            spacing: t.space.md,
            runSpacing: t.space.sm,
            children: [
              _action('pickLog', OnboardingAction.selectLog),
              _refresh(),
            ],
          ),
        ],
      ),
      OnboardingStep.identity => _identity(context),
      OnboardingStep.local => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (appBehavior != null) ...[
            AppBehaviorChoicePanel(
              copy: copy,
              controller: appBehavior!,
              enabled:
                  !view.busy &&
                  f.available &&
                  view.identityReady &&
                  view.modeApplied &&
                  deviceReview?.value.busy != true,
              onSaved: () async {
                // Device review reads the same saved choices from the Host.
                await deviceReview?.refresh();
                await controller.refresh();
              },
            ),
            SizedBox(height: t.space.lg),
          ],
          DeviceReviewPanel(
            copy: copy,
            controller: deviceReview,
            enabled:
                !view.busy &&
                f.available &&
                view.identityReady &&
                view.modeApplied &&
                localStatistics?.value.busy != true,
            onEdit: editDeviceSettings,
            onChanged: controller.refresh,
            interactionBlocked: nativeOverlay?.value.busy == true,
          ),
          SizedBox(height: t.space.lg),
          if (localStatistics != null) ...[
            LocalStatisticsPanel(
              copy: copy,
              controller: localStatistics,
              enabled:
                  !view.busy &&
                  f.available &&
                  view.identityReady &&
                  view.modeApplied &&
                  deviceReview?.value.busy != true &&
                  localHistory?.value.busy != true,
              onChanged: () async {
                await controller.refresh();
                // The recording choice decides whether history can be imported.
                await localHistory?.refresh();
              },
              interactionBlocked: nativeOverlay?.value.busy == true,
            ),
            SizedBox(height: t.space.lg),
          ],
          if (view.mode == OnboardingMode.online) ...[
            Text(copy.text('history.onlineLater')),
            SizedBox(height: t.space.lg),
          ] else if (localHistory != null) ...[
            LocalHistoryPanel(
              copy: copy,
              controller: localHistory!,
              enabled:
                  !view.busy &&
                  f.available &&
                  view.identityReady &&
                  view.modeApplied &&
                  localStatistics?.value.busy != true &&
                  deviceReview?.value.busy != true,
              interactionBlocked: nativeOverlay?.value.busy == true,
              onReset: () async {
                await localStatistics?.refresh();
                await controller.refresh();
              },
            ),
            SizedBox(height: t.space.lg),
          ],
          if (nativeOverlay != null) ...[
            NativeOverlayCheckPanel(
              controller: nativeOverlay!,
              copy: copy,
              enabled:
                  !view.busy &&
                  f.available &&
                  view.identityReady &&
                  view.modeApplied,
              interactionBlocked:
                  deviceReview?.value.busy == true ||
                  localStatistics?.value.busy == true,
              openPreview: openNativePreview,
            ),
            SizedBox(height: t.space.lg),
          ],
          Text(copy.text(f.localSettingsReady ? 'localReady' : 'localPending')),
          _refresh(),
        ],
      ),
      OnboardingStep.online => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(copy.text('sharing')),
          SizedBox(height: t.space.md),
          Text(copy.text('inherit')),
          SizedBox(height: t.space.md),
          Text(
            copy.text(
              f.onlineChoicesReviewed ? 'onlineReady' : 'onlinePending',
            ),
          ),
          SizedBox(height: t.space.lg),
          _action('reviewOnline', OnboardingAction.reviewOnlineChoices),
          _refresh(),
        ],
      ),
      OnboardingStep.verify =>
        recognition == null
            ? Text(copy.text('verify.banner.unsupported.title'))
            : RecognitionCheckPanel(
                copy: copy,
                controller: recognition!,
                confirmedHandle: view.facts.handle,
              ),
      OnboardingStep.summary => _summary(context),
    };
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Material(type: MaterialType.transparency, child: content),
    );
  }

  Widget _mode(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in OnboardingMode.values) ...[
          RadioListTile<OnboardingMode>(
            key: Key('onboarding-mode-${mode.name}'),
            value: mode,
            title: Text(copy.text(mode.name)),
            subtitle: Text(copy.text('${mode.name}Description')),
            toggleable: false,
            enabled: !view.busy && onlineReview?.value.busy != true,
          ),
          SizedBox(height: t.space.md),
        ],
        if (view.mode == OnboardingMode.online) ...[
          if (onlineReview != null)
            OnlineReviewPanel(
              controller: onlineReview!,
              copy: copy,
              enabled: !view.busy && view.facts.available && view.modeApplied,
              onChanged: controller.refresh,
            )
          else ...[
            if (controller.canCancelLogin)
              StarBridgeActionButton(
                controlKey: const Key('onboarding-cancel-login'),
                kind: StarBridgeActionKind.quiet,
                onActivate: _tap(
                  () => controller.run(OnboardingAction.cancelLogin),
                ),
                child: Text(copy.text('cancelLogin')),
              ),
            if (view.facts.signedIn)
              Text(copy.text('signedIn'))
            else
              _action('login', OnboardingAction.login),
            _refresh(),
          ],
        ],
      ],
    );
  }

  Widget _identity(BuildContext context) {
    final t = context.tokens;
    final f = view.facts;
    String status;
    if (view.needsFreshEvidence) {
      status = f.evidence == OnboardingEvidence.missing
          ? 'missing'
          : 'freshRequired';
    } else {
      status = switch (f.evidence) {
        OnboardingEvidence.missing => f.scopeChecked ? 'missing' : 'notChecked',
        OnboardingEvidence.conflict => 'conflict',
        OnboardingEvidence.failed => 'failed',
        OnboardingEvidence.checking => 'checking',
        _ => 'notChecked',
      };
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fact(context, 'version', f.version ?? copy.text('unknown')),
        SizedBox(height: t.space.lg),
        if (f.hasCandidate && !view.needsFreshEvidence) ...[
          _fact(context, 'step.identity', f.handle!),
          SizedBox(height: t.space.md),
          Text(copy.text(f.origin!.name)),
          if (f.origin == OnboardingEvidenceOrigin.confirmedLocal)
            Text(copy.text('confirmedLocalBody')),
          Text('${copy.text('evidenceTime')} · ${f.observedAt!.toLocal()}'),
          SizedBox(height: t.space.md),
          Text(copy.text('localOnly')),
        ] else ...[
          Semantics(
            liveRegion: true,
            child: Text(
              copy.text(status),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (view.needsFreshEvidence) ...[
            SizedBox(height: t.space.md),
            Text(copy.text('enterGame')),
          ],
        ],
        if (view.mode == OnboardingMode.online &&
            !view.onlineIdentityReady) ...[
          SizedBox(height: t.space.md),
          if (!f.localIdentityConfirmed &&
              f.hasCandidate &&
              !view.needsFreshEvidence)
            StarBridgeActionButton(
              controlKey: const Key('onboarding-confirm-local-handle'),
              kind: StarBridgeActionKind.primary,
              onActivate: _tap(
                controller.canConfirmLocalIdentity &&
                        onlineReview?.value.busy != true
                    ? () => controller.run(OnboardingAction.confirmHandle)
                    : null,
              ),
              child: Text(copy.text('onlineReview.confirmLocal')),
            ),
          if (onlineReview != null)
            OnlineReviewPanel(
              controller: onlineReview!,
              copy: copy,
              enabled: !view.busy && f.available && view.identityReady,
              onChanged: controller.refresh,
            )
          else
            Text(copy.text('onlineReview.checkRequired')),
        ] else if (view.mode == OnboardingMode.online &&
            onlineReview != null) ...[
          SizedBox(height: t.space.md),
          OnlineReviewPanel(
            controller: onlineReview!,
            copy: copy,
            enabled: !view.busy && f.available && view.identityReady,
            onChanged: controller.refresh,
          ),
        ],
        SizedBox(height: t.space.lg),
        if (!(view.mode == OnboardingMode.online &&
            onlineReview != null &&
            view.identityReady))
          _refresh(),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final t = context.tokens;
    final entries = buildOnboardingSummary(
      view: view,
      appBehavior: appBehavior?.value,
      device: deviceReview?.value,
      statistics: localStatistics?.value,
      history: localHistory?.value,
      online: onlineReview?.value,
      recognition: recognition?.value,
    );
    Color tone(SummaryStatus status) => switch (status) {
      SummaryStatus.saved => t.colors.success,
      SummaryStatus.skipped => t.colors.textSecondary,
      SummaryStatus.incomplete => t.colors.warning,
      SummaryStatus.failed => t.colors.danger,
    };
    final mine = view.completed && view.mode == OnboardingMode.online
        ? profile
        : null;
    final own = mine?.value;
    final folded = own != null && own.visible && !own.resultsExpanded;
    int count(SummaryStatus status) =>
        entries.where((e) => e.status == status).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.completed) ...[
          Text(
            '✓ ${copy.text('done')}',
            key: const Key('onboarding-done-badge'),
            style: TextStyle(
              color: t.colors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: t.space.md),
        ],
        if (own != null && own.visible) ...[
          OnboardingProfilePanel(
            copy: copy,
            controller: mine!,
            handle: view.facts.handle,
          ),
          SizedBox(height: t.space.md),
          Row(
            key: const Key('onboarding-results-header'),
            children: [
              Expanded(
                child: Text(
                  copy.text('results.title'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final status in SummaryStatus.values)
                if (count(status) > 0)
                  Padding(
                    padding: EdgeInsetsDirectional.only(start: t.space.sm),
                    child: Text(
                      '${copy.text('summary.status.${status.name}')} ${count(status)}',
                      style: TextStyle(color: tone(status)),
                    ),
                  ),
              StarBridgeActionButton(
                controlKey: const Key('onboarding-results-toggle'),
                kind: StarBridgeActionKind.quiet,
                onActivate: _tap(mine.toggleResults),
                child: Text(
                  copy.text(folded ? 'results.expand' : 'results.collapse'),
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.sm),
        ] else if (own != null && own.load != OnboardingProfileLoad.absent) ...[
          Row(
            key: const Key('onboarding-profile-pending'),
            children: [
              Expanded(
                child: Text(
                  copy.text(
                    own.load == OnboardingProfileLoad.failed
                        ? 'profile.loadFailed'
                        : 'profile.loading',
                  ),
                ),
              ),
              if (own.load == OnboardingProfileLoad.failed)
                StarBridgeActionButton(
                  controlKey: const Key('onboarding-profile-retry'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: _tap(mine!.retry),
                  child: Text(copy.text('profile.retry')),
                ),
            ],
          ),
          SizedBox(height: t.space.md),
        ],
        for (final entry in folded ? const <SummaryEntry>[] : entries)
          Padding(
            key: Key('summary-${entry.item.name}'),
            padding: EdgeInsets.only(bottom: t.space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        copy.text('summary.item.${entry.item.name}'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        entry.item == SummaryItem.identity &&
                                entry.status == SummaryStatus.saved &&
                                view.facts.handle != null
                            ? '${view.facts.handle} · ${copy.text(entry.detail)}'
                            : entry.item == SummaryItem.log &&
                                  entry.status == SummaryStatus.saved &&
                                  view.facts.version != null
                            ? '${view.facts.version} · ${copy.text(entry.detail)}'
                            : copy.text(entry.detail),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: t.space.md),
                Text(
                  key: Key('summary-${entry.item.name}-${entry.status.name}'),
                  copy.text(
                    entry.item == SummaryItem.recognition &&
                            entry.status == SummaryStatus.saved
                        ? 'summary.status.passed'
                        : 'summary.status.${entry.status.name}',
                  ),
                  style: TextStyle(
                    color: tone(entry.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        if (!folded) ...[
          Text(copy.text('summary.privacy')),
          SizedBox(height: t.space.md),
        ],
        if (!folded)
          Text(
            copy.text(
              view.readyToFinish || view.completed
                  ? view.mode == OnboardingMode.local
                        ? 'localSummary'
                        : 'onlineSummary'
                  : 'finishPending',
            ),
          ),
        if (!view.completed) _refresh(),
      ],
    );
  }

  Widget _fact(BuildContext context, String label, String value) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StarBridgeIcon(
          StarBridgeIconSemantic.account,
          size: t.icons.medium,
          color: t.colors.accent,
        ),
        SizedBox(width: t.space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                copy.text(label),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SelectableText(
                value,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Native-style tap callback to a suite activation (source unused here).
ValueChanged<InteractionSource>? _tap(VoidCallback? onPressed) =>
    onPressed == null ? null : (_) => onPressed();
