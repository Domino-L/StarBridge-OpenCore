import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'app_behavior_choice_controller.dart';
import 'onboarding_copy.dart';

/// Startup and close behaviour, asked once in first-use setup. Matches the
/// approved preview in StarBridge-DesignPreviews/OnboardingAppBehavior.
class AppBehaviorChoicePanel extends StatelessWidget {
  const AppBehaviorChoicePanel({
    required this.copy,
    required this.controller,
    required this.enabled,
    this.onSaved,
    super.key,
  });
  final OnboardingCopy copy;
  final AppBehaviorChoiceController controller;
  final bool enabled;
  final Future<void> Function()? onSaved;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder<AppBehaviorChoiceView>(
      valueListenable: controller,
      builder: (context, view, _) {
        final active = enabled && view.available && !view.busy;
        final String status;
        final Color tone;
        if (view.busy) {
          status = copy.text('appBehavior.saving');
          tone = t.colors.textSecondary;
        } else if (view.failed) {
          status = copy.text('appBehavior.failed');
          tone = t.colors.danger;
        } else if (view.saved && view.dirty) {
          status = copy.text('appBehavior.dirty');
          tone = t.colors.warning;
        } else if (view.saved) {
          status = copy.text('appBehavior.saved');
          tone = t.colors.success;
        } else if (view.launchAtStartup != null || view.keepInTray != null) {
          status = copy.text('appBehavior.needOne');
          tone = t.colors.warning;
        } else {
          status = copy.text(
            view.available ? 'appBehavior.needBoth' : 'appBehavior.unavailable',
          );
          tone = t.colors.textSecondary;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              copy.text('appBehavior.title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: t.space.sm),
            Text(copy.text('appBehavior.intro')),
            SizedBox(height: t.space.lg),
            AppBehaviorQuestions(
              copy: copy,
              view: view,
              enabled: active,
              onStartup: controller.chooseStartup,
              onClose: controller.chooseClose,
            ),
            SizedBox(height: t.space.lg),
            Wrap(
              spacing: t.space.md,
              runSpacing: t.space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StarBridgeActionButton(
                  controlKey: const Key('app-behavior-save'),
                  kind: StarBridgeActionKind.primary,
                  onActivate: _tap(
                    enabled && view.canSave
                        ? () async {
                            if (await controller.save()) await onSaved?.call();
                          }
                        : null,
                  ),
                  child: Text(
                    copy.text(
                      view.busy ? 'appBehavior.saving' : 'appBehavior.save',
                    ),
                  ),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    status,
                    key: const Key('app-behavior-status'),
                    style: TextStyle(color: tone),
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space.sm),
            Text(
              copy.text('appBehavior.local'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

/// The two startup/close questions, shared by first-use setup and the
/// one-time prompt for existing users. A hidden question was already chosen.
class AppBehaviorQuestions extends StatelessWidget {
  const AppBehaviorQuestions({
    required this.copy,
    required this.view,
    required this.enabled,
    required this.onStartup,
    required this.onClose,
    this.showStartup = true,
    this.showClose = true,
    this.currentStartup,
    this.currentClose,
    super.key,
  });
  final OnboardingCopy copy;
  final AppBehaviorChoiceView view;
  final bool enabled;
  final ValueChanged<bool> onStartup, onClose;
  final bool showStartup, showClose;

  /// Effective values to mark as "当前"; never preselected.
  final bool? currentStartup, currentClose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    String? current(bool? effective, bool value) =>
        effective == value ? copy.text('appBehavior.current') : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showStartup)
          _Question(
            title: copy.text('appBehavior.q.startup'),
            value: view.launchAtStartup,
            enabled: enabled,
            onChanged: onStartup,
            options: [
              _Option(
                key: const Key('app-behavior-startup-auto'),
                value: true,
                name: copy.text('appBehavior.auto.name'),
                recommended: copy.text('appBehavior.recommended'),
                current: current(currentStartup, true),
                fit: copy.text('appBehavior.auto.fit'),
                points: [
                  copy.text('appBehavior.auto.p1'),
                  copy.text('appBehavior.auto.p2'),
                  copy.text('appBehavior.auto.p3'),
                ],
                cost: copy.text('appBehavior.auto.cost'),
              ),
              _Option(
                key: const Key('app-behavior-startup-manual'),
                value: false,
                name: copy.text('appBehavior.manual.name'),
                current: current(currentStartup, false),
                fit: copy.text('appBehavior.manual.fit'),
                points: [
                  copy.text('appBehavior.manual.p1'),
                  copy.text('appBehavior.manual.p2'),
                ],
              ),
            ],
          ),
        if (showStartup && showClose) SizedBox(height: t.space.lg),
        if (showClose)
          _Question(
            title: copy.text('appBehavior.q.close'),
            value: view.keepInTray,
            enabled: enabled,
            onChanged: onClose,
            options: [
              _Option(
                key: const Key('app-behavior-close-tray'),
                value: true,
                name: copy.text('appBehavior.tray.name'),
                recommended: copy.text('appBehavior.recommended'),
                current: current(currentClose, true),
                fit: copy.text('appBehavior.tray.fit'),
                points: [
                  copy.text('appBehavior.tray.p1'),
                  copy.text('appBehavior.tray.p2'),
                ],
              ),
              _Option(
                key: const Key('app-behavior-close-exit'),
                value: false,
                name: copy.text('appBehavior.exit.name'),
                current: current(currentClose, false),
                fit: copy.text('appBehavior.exit.fit'),
                points: [
                  copy.text('appBehavior.exit.p1'),
                  copy.text('appBehavior.exit.p2'),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

final class _Option {
  const _Option({
    required this.key,
    required this.value,
    required this.name,
    required this.fit,
    required this.points,
    this.recommended,
    this.current,
    this.cost,
  });
  final Key key;
  final bool value;
  final String name, fit;
  final String? recommended, current, cost;
  final List<String> points;
}

class _Question extends StatelessWidget {
  const _Question({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.options,
  });
  final String title;
  final bool? value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final List<_Option> options;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label: title,
      child: RadioGroup<bool>(
        groupValue: value,
        onChanged: (selected) {
          if (enabled && selected != null) onChanged(selected);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: t.space.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  for (final option in options)
                    _OptionCard(
                      option: option,
                      selected: value == option.value,
                      enabled: enabled,
                      onTap: () => onChanged(option.value),
                    ),
                ];
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final card in cards) ...[
                        card,
                        if (card != cards.last) SizedBox(height: t.space.md),
                      ],
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final card in cards) ...[
                        Expanded(child: card),
                        if (card != cards.last) SizedBox(width: t.space.md),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final _Option option;
  final bool selected, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: t.colors.textSecondary,
    );
    return Material(
      key: option.key,
      color: t.surfaces.raised.fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.shape.radiusSmall),
        side: BorderSide(
          color: selected ? t.colors.accent : t.surfaces.raised.border,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: StarBridgeActionRow(
        inheritContentStyle: true,
        semanticSelected: selected,
        onActivate: enabled ? (_, _) => onTap() : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            t.space.xs,
            t.space.sm,
            t.space.md,
            t.space.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<bool>(value: option.value, enabled: enabled),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: t.space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: t.space.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(option.name, style: theme.textTheme.titleSmall),
                          if (option.recommended case final label?)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: t.space.xs,
                              ),
                              decoration: BoxDecoration(
                                color: t.colors.accentSoft,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                label,
                                style: small?.copyWith(
                                  color: t.colors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (option.current case final label?)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: t.space.xs,
                              ),
                              decoration: BoxDecoration(
                                color: t.surfaces.raised.border,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(label, style: small),
                            ),
                        ],
                      ),
                      SizedBox(height: t.space.xxs),
                      Text(option.fit, style: small),
                      SizedBox(height: t.space.sm),
                      for (final point in option.points)
                        Padding(
                          padding: EdgeInsets.only(bottom: t.space.xxs),
                          child: Text('• $point'),
                        ),
                      if (option.cost case final cost?) ...[
                        SizedBox(height: t.space.xs),
                        Text(cost, style: small),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Native-style tap callback to a suite activation (source unused here).
ValueChanged<InteractionSource>? _tap(VoidCallback? onPressed) =>
    onPressed == null ? null : (_) => onPressed();
