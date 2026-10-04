import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/shell/chrome/overlay_source_labels.dart';
import '../../app/shell/widgets/overlay_source_menu.dart';
import 'overlay_scene_controller.dart';
import 'overlay_scene_projection.dart';

class OverlayScenePicker extends StatelessWidget {
  const OverlayScenePicker({
    required this.controller,
    this.compact = false,
    super.key,
  });
  final OverlaySceneController controller;
  final bool compact;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<OverlaySceneState>(
        valueListenable: controller.projection,
        builder: (context, state, _) {
          final strings = AppStrings.of(context);
          final view = projectOverlayScene(state);
          final menu = OverlaySourceMenu(
            projection: view,
            onSelected: controller.select,
            triggerKey: const Key('overlay-source-picker'),
          );
          if (compact) {
            return Tooltip(
              message: strings.text(
                view.fallbackReasonKey ?? overlaySourceHint(view),
              ),
              child: menu,
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.text('overlay.source.title'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                menu,
                Text(
                  strings.text(overlaySourceHint(view)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  strings.text(
                    view.fallbackReasonKey ?? 'overlay.source.ready',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      );
}
