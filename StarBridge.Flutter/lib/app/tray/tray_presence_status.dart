import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../localization/app_strings.dart';
import '../shell/chrome/presence_color.dart';
import '../shell/chrome/shell_chrome_projection.dart';
import 'tray_quick_panel_copy.dart';

/// Read the exact same listenable as the avatar menu. Never infer availability
/// from the tray process being alive or save a separate presence preference.
class TrayPresenceStatus extends StatelessWidget {
  const TrayPresenceStatus({this.projection, super.key});
  final ValueListenable<ShellChromeProjection>? projection;

  @override
  Widget build(BuildContext context) {
    final source = projection;
    if (source == null) return _status(context, 'presence.unknown');
    return ValueListenableBuilder<ShellChromeProjection>(
      valueListenable: source,
      builder: (context, state, _) => _status(context, state.presenceKey),
    );
  }

  Widget _status(BuildContext context, String key) {
    final safeKey = switch (key) {
      'presence.online' ||
      'presence.offline' ||
      'presence.away' ||
      'presence.inGame' ||
      'presence.unknown' => key,
      _ => 'presence.unknown',
    };
    final strings = AppStrings.resolve(Localizations.localeOf(context));
    final resolved = strings.text(safeKey);
    // The feature worktree predates several canonical presence translations.
    final label = resolved == safeKey
        ? trayQuickPanelText(context, safeKey)
        : resolved;
    final title = trayQuickPanelText(context, 'presence');
    return Semantics(
      label: '$title：$label',
      child: ExcludeSemantics(
        child: Row(
          key: const Key('tray-presence-status'),
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.tokens.colors.textSecondary),
              ),
            ),
            const SizedBox(width: 12),
            DecoratedBox(
              key: const Key('tray-presence-dot'),
              decoration: BoxDecoration(
                color: presenceColor(context.tokens.colors, safeKey),
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 7),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                key: const Key('tray-presence-label'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
