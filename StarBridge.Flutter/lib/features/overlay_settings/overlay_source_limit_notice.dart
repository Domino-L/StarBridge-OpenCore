import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_scene_controller.dart';
import 'overlay_source_binding_field.dart';
import 'overlay_chat_sources_field.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';

/// Visibility follows Host's stable admission result, never a local cache timer.
class OverlaySourceLimitNotice extends StatelessWidget {
  const OverlaySourceLimitNotice({
    required this.module,
    this.scenes,
    super.key,
  });
  final OverlayWorkspaceModule module;
  final OverlaySceneController? scenes;

  @override
  Widget build(BuildContext context) {
    final copy = AppStrings.of(context).text;
    return Container(
      key: const Key('overlay-source-limit'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: context.tokens.colors.warning),
      ),
      child: Row(
        children: [
          Expanded(child: Text(copy('overlay.source.limit'))),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ValueListenableBuilder<OverlayWorkspaceProjection>(
                valueListenable: module.projection,
                builder: (context, value, _) => AlertDialog(
                  title: Text(copy('overlay.source.adjust')),
                  scrollable: true,
                  content: SizedBox(
                    width: 460,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(copy('overlay.source.limitHelp')),
                        for (final source in OverlaySourceModule.values) ...[
                          const SizedBox(height: 16),
                          Text(
                            copy(
                              'overlay.workspace.group.${source == OverlaySourceModule.overview ? 'fleetOverview' : source.name}',
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (value.sources != null &&
                              source == OverlaySourceModule.chat)
                            OverlayChatSourcesField(
                              value: value.sources!,
                              scenes: scenes,
                              onChanged: value.busy
                                  ? null
                                  : module.updateChatSources,
                              onSingleChanged: value.busy
                                  ? null
                                  : (binding) => module.updateModuleSource(
                                      source,
                                      binding,
                                    ),
                            )
                          else if (value.sources != null)
                            OverlaySourceBindingField(
                              value: value.sources!.forModule(source),
                              scenes: scenes,
                              onChanged: value.busy
                                  ? null
                                  : (binding) => module.updateModuleSource(
                                      source,
                                      binding,
                                    ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(copy('overlay.source.done')),
                    ),
                  ],
                ),
              ),
            ),
            child: Text(copy('overlay.source.adjust')),
          ),
        ],
      ),
    );
  }
}
