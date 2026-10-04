import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_preset_transfer.dart';
import 'overlay_workspace_layout_editor.dart';

/// A local sample of the shared layout, never live messages or member data.
class OverlaySharedPresetCard extends StatelessWidget {
  const OverlaySharedPresetCard({
    required this.name,
    required this.onInspect,
    this.preview,
    super.key,
  });
  final String name;
  final OverlayPresetTransfer? preview;
  final VoidCallback? onInspect;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final value = preview;
    return SizedBox(
      width: 360,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('overlay.shareCard.kind'),
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: theme.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              if (value != null) ...[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: FocusScope(
                        canRequestFocus: false,
                        child: OverlayWorkspaceLayoutWorkbench(
                          layout: value.layout,
                          settings: value.settings,
                          sources: value.sources,
                          canvasOnly: true,
                          showHiddenModules: false,
                          onChanged: (_, _) {},
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${strings.text('overlay.shareCard.appearance')} · ${strings.text('overlay.workspace.option.${value.settings['requestedSkin']}')}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    for (final entry in const {
                      'notice': 'showNotice',
                      'fleetOverview': 'showSquads',
                      'members': 'showMembers',
                      'chat': 'showChat',
                      'events': 'showEventNotifications',
                      'crosshair': 'showCrosshair',
                    }.entries)
                      if (value.settings[entry.value] == true)
                        strings.text('overlay.workspace.group.${entry.key}'),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ] else
                Text(
                  strings.text('overlay.shareCard.previewUnavailable'),
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: onInspect,
                child: Text(strings.text('overlay.shareCard.inspect')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
