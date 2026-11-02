import 'package:flutter/material.dart';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';

import '../../app/localization/app_strings.dart';
import '../../app/routing/open_destination_intent.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_row.dart';

final class ToolEntry {
  const ToolEntry({
    required this.id,
    required this.titleKey,
    required this.descriptionKey,
    required this.icon,
    required this.route,
  });
  final String id, titleKey, descriptionKey, route;
  final StarBridgeIconSemantic icon;
}

const toolEntries = [
  ToolEntry(
    id: 'exec-hangar',
    titleKey: 'execHangar.title',
    descriptionKey: 'tools.execHangar.description',
    icon: StarBridgeIconSemantic.playtime,
    route: '/tools/exec-hangar',
  ),
];

final class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key, this.entries = toolEntries});
  final List<ToolEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final content = SingleChildScrollView(
      padding: EdgeInsets.all(tokens.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('navigation.tools'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            strings.text('tools.description'),
            style: TextStyle(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / 360).floor().clamp(1, 3);
              final width =
                  (constraints.maxWidth - tokens.space.md * (columns - 1)) /
                  columns;
              return Wrap(
                spacing: tokens.space.md,
                runSpacing: tokens.space.md,
                children: [
                  for (final entry in entries)
                    SizedBox(
                      width: width,
                      child: Material(
                        color: tokens.surfaces.panel.fill,
                        shape: RoundedRectangleBorder(
                          borderRadius: tokens.shape.medium,
                          side: BorderSide(color: tokens.surfaces.panel.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: StarBridgeActionRow(
                          controlKey: Key('tool-${entry.id}'),
                          baseRadius: tokens.shape.radiusMedium,
                          onActivate: (context, _) => Actions.invoke(
                            context,
                            OpenDestinationIntent(entry.route),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(tokens.space.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                StarBridgeIcon(
                                  entry.icon,
                                  size: 30,
                                  color: tokens.colors.accent,
                                ),
                                SizedBox(height: tokens.space.md),
                                Text(
                                  strings.text(entry.titleKey),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  strings.text(entry.descriptionKey),
                                  style: TextStyle(
                                    color: tokens.colors.textSecondary,
                                  ),
                                ),
                                SizedBox(height: tokens.space.lg),
                                Row(
                                  children: [
                                    Text(
                                      strings.text('tools.open'),
                                      style: TextStyle(
                                        color: tokens.colors.accent,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    StarBridgeIcon(
                                      StarBridgeIconSemantic.forward,
                                      size: 18,
                                      color: tokens.colors.accent,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
    return LoadingContentProbe(
      route: '/tools',
      status: entries.isEmpty
          ? LoadingContentStatus.empty
          : LoadingContentStatus.data,
      items: entries.length,
      child: content,
    );
  }
}
