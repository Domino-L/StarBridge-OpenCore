import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/feature_registry.dart';
import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../game_log/game_log_controller.dart';
import 'overlay_settings_module.dart';
import 'overlay_settings_page.dart';
import 'menu_additional_settings_editors.dart';

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
  final completion = captureStarBridgeActivationCompletion();
  return runStarBridgeActivation(
    StarBridgeActivationOrigin.sourceOf(context),
    () async {
      try {
        return await _confirmWorkspaceLeave(context, module);
      } finally {
        completion(currentStarBridgeActivationSource);
      }
    },
  );
}

Future<bool> _confirmWorkspaceLeave(
  BuildContext context,
  OverlaySettingsModule module,
) async {
  final menu = module.menuDraft;
  if (menu != null && menu.dirty) {
    if (menu.busy) return false;
    final settings = menu.settings;
    final additional = menu.additional;
    final edits = additional?.edits;
    var unchanged = true;
    void watch() {
      if (!mapEquals(settings, menu.settings) ||
          !identical(additional, menu.additional) ||
          edits != menu.additional?.edits ||
          !menu.dirty) {
        unchanged = false;
      }
    }

    bool canApply() =>
        context.mounted &&
        identical(module.menuDraft, menu) &&
        unchanged &&
        !menu.busy;
    menu.addListener(watch);
    try {
      final choice = await _leavePrompt(context, menu: true);
      if (!context.mounted || !canApply()) return false;
      if (choice == _OverlayWorkspaceLeaveChoice.discard) {
        menu.discard();
      } else if (choice == _OverlayWorkspaceLeaveChoice.save) {
        if (!await confirmMenuSettingsSave(context, menu, canSave: canApply)) {
          return false;
        }
      } else {
        return false;
      }
    } finally {
      menu.removeListener(watch);
    }
    if (!context.mounted || !identical(module.menuDraft, menu) || menu.dirty) {
      return false;
    }
  }
  final workspace = module.workspace;
  bool clean() =>
      module.menuDraft?.dirty != true &&
      module.workspace?.projection.value.dirty != true;
  if (workspace == null || !workspace.projection.value.dirty) return clean();
  if (workspace.projection.value.busy) return false;
  // Edits save on their own; leaving only waits for the last one. The prompt
  // below remains for a save that failed, where retry or discard is a choice.
  if (await workspace.save()) return context.mounted && clean();
  if (!context.mounted || workspace.projection.value.busy) return false;
  Object token() {
    final p = workspace.projection.value;
    return (
      p.snapshot,
      p.settings,
      p.layout,
      p.hotkey,
      p.renderMode,
      p.sources,
      p.appearanceOptions,
      p.dirty,
    );
  }

  final before = token();
  var unchanged = true;
  void watch() {
    if (token() != before) unchanged = false;
  }

  workspace.projection.addListener(watch);
  late final _OverlayWorkspaceLeaveChoice? choice;
  try {
    choice = await _leavePrompt(context, menu: false);
  } finally {
    workspace.projection.removeListener(watch);
  }
  if (!context.mounted || !unchanged || workspace.projection.value.busy) {
    return false;
  }
  switch (choice) {
    case _OverlayWorkspaceLeaveChoice.save:
      if (!await workspace.save()) return false;
    case _OverlayWorkspaceLeaveChoice.discard:
      workspace.discardChanges();
    default:
      return false;
  }
  return context.mounted && clean();
}

Future<_OverlayWorkspaceLeaveChoice?> _leavePrompt(
  BuildContext context, {
  required bool menu,
}) {
  final strings = AppStrings.of(context);
  final prefix = menu ? 'menu' : 'overlay';
  String copy(String menuKey, String overlayKey) =>
      strings.text(menu ? menuKey : overlayKey);
  return showStarBridgeDialog<_OverlayWorkspaceLeaveChoice>(
    context,
    source: currentStarBridgeActivationSource,
    barrierDismissible: false,
    builder: (context) => StarBridgeInteractionConfiguration(
      suite: InteractionScope.of(context).suite,
      reduceMotion: InteractionScope.of(context).reduceMotion,
      child: AlertDialog(
        key: Key('$prefix-unsaved-leave-dialog'),
        title: Text(
          copy('menu.workspace.leaveTitle', 'overlay.workspace.leave.title'),
        ),
        content: Text(
          copy('menu.workspace.leaveBody', 'overlay.workspace.leave.body'),
        ),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: Key('$prefix-unsaved-leave-cancel'),
            onActivate: (source) => dismissStarBridgeDialog(
              context,
              source: source,
              result: _OverlayWorkspaceLeaveChoice.cancel,
            ),
            child: Text(
              copy('menu.workspace.stay', 'overlay.workspace.leave.cancel'),
            ),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: Key('$prefix-unsaved-leave-discard'),
            onActivate: (source) => dismissStarBridgeDialog(
              context,
              source: source,
              result: _OverlayWorkspaceLeaveChoice.discard,
            ),
            child: Text(
              copy('menu.workspace.discard', 'overlay.workspace.discard'),
            ),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: Key('$prefix-unsaved-leave-save'),
            onActivate: (source) => dismissStarBridgeDialog(
              context,
              source: source,
              result: _OverlayWorkspaceLeaveChoice.save,
            ),
            child: Text(
              copy('menu.workspace.save', 'overlay.workspace.leave.retry'),
            ),
          ),
        ],
      ),
    ),
  );
}
