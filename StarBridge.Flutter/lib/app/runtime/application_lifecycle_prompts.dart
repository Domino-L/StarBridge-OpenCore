import 'package:flutter/material.dart';

import '../localization/app_strings.dart';

Future<bool?> showFirstCloseBehaviorPrompt(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final strings = AppStrings.of(dialogContext);
      return AlertDialog(
        key: const Key('first-close-behavior-dialog'),
        title: Text(strings.text('settings.lifecycle.close.title')),
        content: Text(strings.text('settings.lifecycle.close.body')),
        actions: [
          TextButton(
            key: const Key('first-close-exit'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.text('settings.lifecycle.close.exit')),
          ),
          FilledButton(
            key: const Key('first-close-background'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
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
  return showDialog<void>(
    context: context,
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
                SwitchListTile(
                  key: const Key('first-startup-enabled'),
                  contentPadding: EdgeInsets.zero,
                  value: selected,
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() {
                          selected = value;
                          saveFailed = false;
                        }),
                  title: Text(
                    strings.text('settings.lifecycle.startup.option'),
                  ),
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
            FilledButton(
              key: const Key('first-startup-continue'),
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() {
                        saving = true;
                        saveFailed = false;
                      });
                      final saved = await onSave(selected);
                      if (!dialogContext.mounted) {
                        return;
                      }
                      if (saved) {
                        Navigator.of(dialogContext).pop();
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
