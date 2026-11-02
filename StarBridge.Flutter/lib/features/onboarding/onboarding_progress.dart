import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'onboarding_copy.dart';
import 'onboarding_models.dart';

/// Direction C breakpoints (window width). Wide shows a horizontal stepper,
/// medium a left rail, narrow a thin segmented bar.
abstract final class OnboardingProgressLayout {
  static const wide = 1280.0;
  static const medium = 900.0;
}

enum OnboardingProgressKind { horizontal, rail, bar }

OnboardingProgressKind onboardingProgressKind(double width) =>
    width >= OnboardingProgressLayout.wide
    ? OnboardingProgressKind.horizontal
    : width >= OnboardingProgressLayout.medium
    ? OnboardingProgressKind.rail
    : OnboardingProgressKind.bar;

/// One short, observed status line per step. Never claims a step is done
/// because the user moved past it: done steps show what was confirmed.
String onboardingStepStatus(
  OnboardingCopy copy,
  OnboardingView view,
  OnboardingStep step, {
  required bool done,
  required bool current,
  String? verifyStatus,
}) {
  if (view.completed) return copy.text('progress.saved');
  if (current) return copy.text('progress.current');
  if (!done) return '';
  final f = view.facts;
  return switch (step) {
    OnboardingStep.mode => copy.text(
      view.mode == OnboardingMode.online ? 'progress.online' : 'progress.local',
    ),
    OnboardingStep.log => f.version ?? copy.text('progress.done'),
    OnboardingStep.identity => f.handle ?? copy.text('progress.done'),
    OnboardingStep.verify => verifyStatus ?? copy.text('progress.done'),
    _ => copy.text('progress.done'),
  };
}

class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    required this.kind,
    required this.view,
    required this.copy,
    required this.steps,
    this.verifyStatus,
    super.key,
  });
  final OnboardingProgressKind kind;
  final OnboardingView view;
  final OnboardingCopy copy;
  final List<OnboardingStep> steps;
  final String? verifyStatus;

  int get _current => view.completed ? steps.length : steps.indexOf(view.step);

  Widget _node(BuildContext context, int index) {
    final t = context.tokens;
    final done = index < _current;
    final now = index == _current;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? t.colors.success : t.surfaces.ground.fill,
        border: Border.all(
          width: 2,
          color: done
              ? t.colors.success
              : now
              ? t.colors.accent
              : t.surfaces.raised.border,
        ),
      ),
      child: done
          ? Text(
              '✓',
              style: TextStyle(
                fontSize: 12,
                height: 1,
                fontWeight: FontWeight.w700,
                color: t.surfaces.ground.fill,
              ),
            )
          : Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: now ? t.colors.accent : t.colors.textSecondary,
              ),
            ),
    );
  }

  Widget _label(BuildContext context, int index) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final done = index < _current;
    final now = index == _current;
    final status = onboardingStepStatus(
      copy,
      view,
      steps[index],
      done: done,
      current: now,
      verifyStatus: verifyStatus,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          copy.step(steps[index]),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: now ? t.colors.accent : t.colors.textPrimary,
          ),
        ),
        if (status.isNotEmpty)
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: theme.textTheme.bodySmall?.copyWith(
              color: done ? t.colors.success : t.colors.textSecondary,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final line = t.surfaces.raised.border;
    return Semantics(
      container: true,
      label: copy.text('progress.label'),
      child: switch (kind) {
        OnboardingProgressKind.horizontal => Container(
          key: const Key('onboarding-progress-horizontal'),
          padding: EdgeInsets.only(bottom: t.space.md),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < steps.length; i++)
                Expanded(
                  child: Semantics(
                    selected: i == _current,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _node(context, i),
                        SizedBox(width: t.space.sm),
                        Flexible(child: _label(context, i)),
                        if (i < steps.length - 1)
                          Expanded(
                            child: Container(
                              height: 2,
                              margin: EdgeInsets.only(
                                top: 10,
                                left: t.space.sm,
                                right: t.space.sm,
                              ),
                              color: i < _current ? t.colors.success : line,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        OnboardingProgressKind.rail => Container(
          key: const Key('onboarding-progress-rail'),
          width: 232,
          padding: EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.md, 0),
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < steps.length; i++)
                Semantics(
                  selected: i == _current,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          children: [
                            _node(context, i),
                            if (i < steps.length - 1)
                              Expanded(
                                child: Container(
                                  width: 2,
                                  constraints: const BoxConstraints(
                                    minHeight: 14,
                                  ),
                                  color: i < _current ? t.colors.success : line,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(width: t.space.sm),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: t.space.md),
                            child: _label(context, i),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        OnboardingProgressKind.bar => Column(
          key: const Key('onboarding-progress-bar'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: i < _current
                            ? t.colors.success
                            : i == _current
                            ? t.colors.accent
                            : line,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: t.space.xs),
            Text(
              view.completed
                  ? copy
                        .text('progress.allDone')
                        .replaceAll('{total}', '${steps.length}')
                  : copy
                        .text('progress.where')
                        .replaceAll('{n}', '${_current + 1}')
                        .replaceAll('{total}', '${steps.length}')
                        .replaceAll('{name}', copy.step(view.step)),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: t.colors.textSecondary),
            ),
          ],
        ),
      },
    );
  }
}
