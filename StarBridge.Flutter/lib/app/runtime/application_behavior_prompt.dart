import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/onboarding/app_behavior_choice_controller.dart';
import '../../features/onboarding/app_behavior_choice_panel.dart';
import '../../features/onboarding/onboarding_copy.dart';
import '../preferences/app_preferences_port.dart';

/// One-time startup/close prompt for existing users who skip first-use setup.
/// Uses the same questions as setup and asks only what was never chosen.
/// Returns true once both choices are saved; false when deferred.
Future<bool> showApplicationBehaviorPrompt(
  BuildContext context,
  AppPreferencesPort preferences,
) async {
  final saved = await showStarBridgeDialog<bool>(
    context,
    barrierDismissible: false,
    builder: (_) => _ApplicationBehaviorPrompt(preferences: preferences),
  );
  return saved == true;
}

class _ApplicationBehaviorPrompt extends StatefulWidget {
  const _ApplicationBehaviorPrompt({required this.preferences});
  final AppPreferencesPort preferences;

  @override
  State<_ApplicationBehaviorPrompt> createState() =>
      _ApplicationBehaviorPromptState();
}

class _ApplicationBehaviorPromptState
    extends State<_ApplicationBehaviorPrompt> {
  late final AppBehaviorChoiceController _controller =
      AppBehaviorChoiceController(widget.preferences);
  // Fixed when the prompt opens: a saved answer must not hide its question.
  late final _behavior =
      widget.preferences.projection.value.confirmed?.applicationBehavior;
  late final bool _askStartup = _behavior?.startupChoiceMade != true;
  late final bool _askClose = _behavior?.closeBehaviorChoiceMade != true;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (await _controller.save() && mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final copy = OnboardingCopy(Localizations.localeOf(context));
    final both = _askStartup && _askClose;
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: t.colors.textSecondary);
    return ValueListenableBuilder<AppBehaviorChoiceView>(
      valueListenable: _controller,
      builder: (context, view, _) {
        final ready = view.launchAtStartup != null && view.keepInTray != null;
        final (status, tone) = _done
            ? (copy.text('appBehavior.saved'), t.colors.success)
            : view.busy
            ? (copy.text('appBehavior.saving'), t.colors.textSecondary)
            : view.failed
            ? (copy.text('appBehavior.failed'), t.colors.danger)
            : ready
            ? (
                copy.text(
                  both
                      ? 'behaviorPrompt.local.both'
                      : 'behaviorPrompt.local.one',
                ),
                t.colors.textSecondary,
              )
            : (
                copy.text(
                  both ? 'behaviorPrompt.need.both' : 'behaviorPrompt.need.one',
                ),
                t.colors.textSecondary,
              );
        final chosen = !_askStartup
            ? copy
                  .text('behaviorPrompt.chosen.startup')
                  .replaceAll(
                    '{choice}',
                    copy.text(
                      _behavior?.launchAtStartup == true
                          ? 'appBehavior.auto.name'
                          : 'appBehavior.manual.name',
                    ),
                  )
            : !_askClose
            ? copy
                  .text('behaviorPrompt.chosen.close')
                  .replaceAll(
                    '{choice}',
                    copy.text(
                      _behavior?.keepRunningInBackground == true
                          ? 'appBehavior.tray.name'
                          : 'appBehavior.exit.name',
                    ),
                  )
            : null;
        return AlertDialog(
          key: const Key('app-behavior-prompt'),
          title: Text(
            copy.text(
              both
                  ? 'behaviorPrompt.title.both'
                  : _askStartup
                  ? 'behaviorPrompt.title.startup'
                  : 'behaviorPrompt.title.close',
            ),
          ),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    copy.text(
                      both
                          ? 'behaviorPrompt.intro.both'
                          : 'behaviorPrompt.intro.one',
                    ),
                    style: small,
                  ),
                  if (chosen != null) ...[
                    SizedBox(height: t.space.md),
                    Text(
                      '✓ $chosen',
                      key: const Key('app-behavior-prompt-chosen'),
                      style: small,
                    ),
                  ],
                  SizedBox(height: t.space.lg),
                  AppBehaviorQuestions(
                    copy: copy,
                    view: view,
                    enabled: view.available && !view.busy && !_done,
                    onStartup: _controller.chooseStartup,
                    onClose: _controller.chooseClose,
                    showStartup: _askStartup,
                    showClose: _askClose,
                    currentStartup: _behavior?.launchAtStartup,
                    currentClose: _behavior?.keepRunningInBackground,
                  ),
                  SizedBox(height: t.space.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      status,
                      key: const Key('app-behavior-prompt-status'),
                      style: TextStyle(color: tone),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (!_done)
              StarBridgeActionButton(
                controlKey: const Key('app-behavior-prompt-later'),
                kind: StarBridgeActionKind.quiet,
                onActivate: view.busy
                    ? null
                    : (source) => dismissStarBridgeDialog(
                        context,
                        result: false,
                        source: source,
                      ),
                child: Text(copy.text('behaviorPrompt.later')),
              ),
            StarBridgeActionButton(
              controlKey: const Key('app-behavior-prompt-save'),
              kind: StarBridgeActionKind.primary,
              onActivate: _done
                  ? (source) => dismissStarBridgeDialog(
                      context,
                      result: true,
                      source: source,
                    )
                  : view.canSave
                  ? (_) => _save()
                  : null,
              child: Text(
                copy.text(
                  _done
                      ? 'behaviorPrompt.done'
                      : view.failed
                      ? 'behaviorPrompt.retry'
                      : 'behaviorPrompt.save',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
