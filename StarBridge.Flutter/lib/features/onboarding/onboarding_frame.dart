import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';

import 'package:flutter/material.dart';

import '../../design_system/brand/brand_lockup.dart';
import '../../design_system/brand/brand_lockup_spec.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'onboarding_copy.dart';
import 'onboarding_models.dart';
import 'onboarding_progress.dart';

class OnboardingFrame extends StatelessWidget {
  const OnboardingFrame({
    required this.view,
    required this.copy,
    required this.body,
    required this.canContinue,
    required this.onNext,
    required this.onBack,
    required this.onClose,
    this.interactionBlocked = false,
    this.canGoBack = true,
    this.showWelcomeIntro = true,
    this.verifyStatus,
    this.nextLabelKey,
    super.key,
  });
  final OnboardingView view;
  final OnboardingCopy copy;
  final Widget body;
  final bool canContinue;
  final VoidCallback onNext, onBack, onClose;
  final bool interactionBlocked;
  final bool canGoBack;
  final bool showWelcomeIntro;

  /// Observed recognition-check result for the progress line, if any.
  final String? verifyStatus;

  /// Copy key overriding the primary button on the current step.
  final String? nextLabelKey;

  Widget _content(BuildContext context) {
    final t = context.tokens;
    return SingleChildScrollView(
      key: const Key('onboarding-scroll'),
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: t.space.xl),
              Semantics(
                header: true,
                child: Text(
                  view.completed
                      ? copy.text('done.title')
                      : copy.title(view.step),
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ),
              SizedBox(height: t.space.sm),
              Text(
                view.completed
                    ? copy.text(
                        view.mode == OnboardingMode.online
                            ? 'done.lead.online'
                            : 'done.lead.local',
                      )
                    : copy.description(view.step),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: t.colors.textSecondary),
              ),
              SizedBox(height: t.space.xl),
              if (view.busy || view.error || !view.facts.available) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    copy.text(
                      view.busy
                          ? 'busy'
                          : view.error
                          ? 'error'
                          : 'unavailable',
                    ),
                    style: TextStyle(
                      color: view.error
                          ? t.colors.warning
                          : t.colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(height: t.space.md),
              ],
              body,
              SizedBox(height: t.space.xxl),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final steps = view.steps
        .where((step) => showWelcomeIntro || step != OnboardingStep.welcome)
        .toList();
    return Scaffold(
      key: const Key('onboarding-page'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final kind = onboardingProgressKind(box.maxWidth);
            final progress = OnboardingProgress(
              kind: kind,
              view: view,
              copy: copy,
              steps: steps,
              verifyStatus: verifyStatus,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.all(t.space.lg),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: t.space.md,
                    runSpacing: t.space.sm,
                    children: [
                      // Same mark + wordmark as the app shell navigation.
                      Semantics(
                        label: copy.text('brand'),
                        child: const BrandLockup(
                          scale: BrandLockupScale.navigationExpanded,
                        ),
                      ),
                      StarBridgeActionButton(
                        controlKey: const Key('onboarding-close'),
                        kind: StarBridgeActionKind.quiet,
                        onActivate: _tap(
                          view.busy || interactionBlocked ? null : onClose,
                        ),
                        child: Text(
                          copy.text(view.completed ? 'closePlain' : 'close'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (kind != OnboardingProgressKind.rail)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: t.space.lg),
                    child: progress,
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (kind == OnboardingProgressKind.rail)
                        SingleChildScrollView(child: progress),
                      Expanded(child: _content(context)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.all(t.space.lg),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: t.space.md,
                    runSpacing: t.space.sm,
                    children: [
                      if (!view.completed &&
                          view.step != OnboardingStep.welcome &&
                          canGoBack)
                        StarBridgeActionButton(
                          controlKey: const Key('onboarding-back'),
                          kind: StarBridgeActionKind.secondary,
                          onActivate: _tap(
                            view.busy || interactionBlocked ? null : onBack,
                          ),
                          child: Text(copy.text('back')),
                        ),
                      StarBridgeActionButton(
                        controlKey: const Key('onboarding-next'),
                        kind: StarBridgeActionKind.primary,
                        onActivate: _tap(
                          view.completed
                              ? onClose
                              : canContinue
                              ? onNext
                              : null,
                        ),
                        child: Text(
                          copy.text(
                            view.completed
                                ? 'enterApp'
                                : nextLabelKey ??
                                      (view.step == OnboardingStep.identity &&
                                              !view.facts.localIdentityConfirmed
                                          ? 'confirm'
                                          : view.step == OnboardingStep.summary
                                          ? 'finish'
                                          : 'next'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Native-style tap callback to a suite activation (source unused here).
ValueChanged<InteractionSource>? _tap(VoidCallback? onPressed) =>
    onPressed == null ? null : (_) => onPressed();
