import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'continuous_play_connected_panel.dart';
import 'continuous_play_controller.dart';
import 'settings_entry_catalog.dart';

Future<void> showContinuousPlayDialog(
  BuildContext context,
  ContinuousPlayController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    key: const Key('settings-entry-continuous-play'),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: StarBridgeSurface(
      role: SurfaceRole.floating,
      child: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: ContinuousPlayConnectedPanel(controller: controller),
            ),
            SizedBox(height: context.tokens.space.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('settings-entry-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(settingsEntryText(AppStrings.of(context), 'close')),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
