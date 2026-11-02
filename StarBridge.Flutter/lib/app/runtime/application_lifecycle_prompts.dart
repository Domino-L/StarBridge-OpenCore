import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../features/common/social_read_activity.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

Future<bool?> showFirstCloseBehaviorPrompt(BuildContext context) {
  return showStarBridgeDialog<bool>(
    context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final strings = AppStrings.of(dialogContext);
      return AlertDialog(
        key: const Key('first-close-behavior-dialog'),
        title: Text(strings.text('settings.lifecycle.close.title')),
        content: Text(strings.text('settings.lifecycle.close.body')),
        actions: [
          StarBridgeActionButton(
            controlKey: const Key('first-close-exit'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) => dismissStarBridgeDialog(
              dialogContext,
              source: source,
              result: false,
            ),
            child: Text(strings.text('settings.lifecycle.close.exit')),
          ),
          StarBridgeActionButton(
            controlKey: const Key('first-close-background'),
            kind: StarBridgeActionKind.primary,
            onActivate: (source) => dismissStarBridgeDialog(
              dialogContext,
              source: source,
              result: true,
            ),
            child: Text(strings.text('settings.lifecycle.close.background')),
          ),
        ],
      );
    },
  );
}

Future<void> showFirstStartupChoicePrompt(
  BuildContext context, {
  required Future<bool> Function(bool enabled) onSave,
}) {
  var selected = true;
  var saving = false;
  var saveFailed = false;
  var saveRevision = 0;
  var saveSource = InteractionSource.programmatic;
  return showStarBridgeDialog<void>(
    context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final strings = AppStrings.of(dialogContext);
        return AlertDialog(
          key: const Key('first-startup-choice-dialog'),
          title: Text(strings.text('settings.lifecycle.startup.title')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(strings.text('settings.lifecycle.startup.body')),
                const SizedBox(height: 16),
                StarBridgeSwitch.tile(
                  controlKey: const Key('first-startup-enabled'),
                  preserveNativeTile: true,
                  label: strings.text('settings.lifecycle.startup.option'),
                  value: selected,
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() {
                          selected = value;
                          saveFailed = false;
                        }),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 4,
                  child: saving
                      ? KeyedSubtree(
                          key: ValueKey(('startup-save', saveRevision)),
                          child: SocialReadActivity(
                            key: const Key('first-startup-save-activity'),
                            source: saveSource,
                            opening: false,
                            label: strings.text('settings.general.saving'),
                            height: 4,
                          ),
                        )
                      : null,
                ),
                if (saveFailed) ...[
                  const SizedBox(height: 8),
                  Text(
                    strings.text('settings.lifecycle.startup.saveFailed'),
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            StarBridgeActionButton(
              controlKey: const Key('first-startup-continue'),
              kind: StarBridgeActionKind.primary,
              onActivate: saving
                  ? null
                  : (source) async {
                      setDialogState(() {
                        saveSource = source;
                        saveRevision++;
                        saving = true;
                        saveFailed = false;
                      });
                      final saved = await onSave(selected);
                      if (!dialogContext.mounted) {
                        return;
                      }
                      if (saved) {
                        dismissStarBridgeDialog(dialogContext, source: source);
                      } else {
                        setDialogState(() {
                          saving = false;
                          saveFailed = true;
                        });
                      }
                    },
              child: Text(strings.text('settings.lifecycle.startup.continue')),
            ),
          ],
        );
      },
    ),
  );
}

/// Holds the standalone startup prompt while first-use setup will ask startup
/// and close behaviour itself. Releasing it lets the prompt cover users who do
/// not get setup (existing users, official builds or a failed eligibility read).
final class FirstUseChoiceHold {
  FirstUseChoiceHold(this._onRelease);
  final void Function() _onRelease;
  bool _active = false;

  bool get active => _active;

  void set(bool active) {
    if (_active == active) return;
    _active = active;
    if (!active) _onRelease();
  }
}
