import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'overlay_scene_controller.dart';
import 'overlay_scene_projection.dart';

class OverlayScenePicker extends StatelessWidget {
  const OverlayScenePicker({required this.controller, super.key});
  final OverlaySceneController controller;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<OverlaySceneState>(
    valueListenable: controller.projection,
    builder: (context, state, _) {
      final strings = AppStrings.of(context);
      final view = projectOverlayScene(state);
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
            DropdownButton<String>(
              key: const Key('overlay-source-picker'),
              isExpanded: true,
              value: view.preferredSceneId,
              items: [
                for (final option in view.options)
                  DropdownMenuItem(
                    value: option.id,
                    enabled: option.enabled,
                    child: Text(
                      option.label ?? strings.text(option.labelKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: option.enabled
                          ? null
                          : TextStyle(color: Theme.of(context).disabledColor),
                    ),
                  ),
              ],
              onChanged: !view.canChange
                  ? null
                  : (id) {
                      if (id != null) unawaited(controller.select(id));
                    },
            ),
            Text(
              strings.text('overlay.source.hint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              strings.text(view.fallbackReasonKey ?? 'overlay.source.ready'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    },
  );
}
