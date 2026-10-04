import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Saved binding, not the editor draft. This is a hint, not another editor.
class OverlayShortcutSummary extends StatelessWidget {
  const OverlayShortcutSummary({
    required this.binding,
    required this.enabled,
    required this.state,
    super.key,
  });
  final String? binding;
  final bool enabled;
  final String state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final status = !enabled
        ? 'disabled'
        : switch (state) {
            'registered' || 'gameCompatibleOnly' || 'desktopOnly' => state,
            'conflictWithInformation' || 'conflict' => 'conflict',
            'modifierRequired' || 'reserved' || 'invalid' => 'invalid',
            'failed' => 'failed',
            _ => 'unavailable',
          };
    final ready = const {
      'registered',
      'gameCompatibleOnly',
      'desktopOnly',
    }.contains(status);
    final description = strings.text('overlay.runtime.hotkey.$status');
    return Tooltip(
      message: description,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          Text(
            strings.text('overlay.workspace.hotkey'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.tokens.colors.textSecondary),
          ),
          Text(binding ?? '—', style: Theme.of(context).textTheme.labelLarge),
          if (!ready)
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: enabled && status != 'unavailable'
                    ? context.tokens.colors.warning
                    : context.tokens.colors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
