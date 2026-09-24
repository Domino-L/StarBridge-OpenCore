import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/feature_registry.dart';
import '../../app/localization/app_strings.dart';
import '../game_log/game_log_controller.dart';
import 'overlay_settings_module.dart';
import 'overlay_settings_page.dart';

FeatureDescriptor createOverlaySettingsFeature(
  OverlaySettingsModule module, {
  ValueListenable<GameLogView>? gameLog,
}) => FeatureDescriptor(
  id: 'overlay-settings',
  route: '/overlay',
  labelKey: 'navigation.overlay',
  descriptionKey: 'navigation.overlay.description',
  icon: StarBridgeIconSemantic.overlay,
  navigationRegion: NavigationRegion.personal,
  order: 20,
  buildDestination: (_) =>
      OverlaySettingsPage(module: module, gameLog: gameLog),
  confirmLeave: (context) => confirmOverlayWorkspaceLeave(context, module),
);

enum _OverlayWorkspaceLeaveChoice { save, discard, cancel }

Future<bool> confirmOverlayWorkspaceLeave(
  BuildContext context,
  OverlaySettingsModule module,
) async {
  final workspace = module.workspace;
  if (workspace == null || !workspace.projection.value.dirty) return true;
  final strings = AppStrings.of(context);
  final choice = await showDialog<_OverlayWorkspaceLeaveChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      key: const Key('overlay-unsaved-leave-dialog'),
      title: Text(strings.text('overlay.workspace.leave.title')),
      content: Text(strings.text('overlay.workspace.leave.body')),
      actions: [
        TextButton(
          key: const Key('overlay-unsaved-leave-cancel'),
          onPressed: () =>
              Navigator.pop(context, _OverlayWorkspaceLeaveChoice.cancel),
          child: Text(strings.text('overlay.workspace.leave.cancel')),
        ),
        TextButton(
          key: const Key('overlay-unsaved-leave-discard'),
          onPressed: () =>
              Navigator.pop(context, _OverlayWorkspaceLeaveChoice.discard),
          child: Text(strings.text('overlay.workspace.discard')),
        ),
        FilledButton(
          key: const Key('overlay-unsaved-leave-save'),
          onPressed: () =>
              Navigator.pop(context, _OverlayWorkspaceLeaveChoice.save),
          child: Text(strings.text('overlay.workspace.save')),
        ),
      ],
    ),
  );
  return switch (choice) {
    _OverlayWorkspaceLeaveChoice.save => await workspace.save(),
    _OverlayWorkspaceLeaveChoice.discard => () {
      workspace.discardChanges();
      return true;
    }(),
    _ => false,
  };
}
