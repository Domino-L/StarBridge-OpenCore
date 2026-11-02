import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../app/shell/chrome/overlay_source_labels.dart';
import 'overlay_scene_controller.dart';
import 'overlay_scene_projection.dart';
import 'overlay_settings_help.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';

/// The one place that answers "whose information does the overlay show".
/// It shows the remembered choice, what it resolves to and why; the in-game
/// panel and the title bar edit the same choice.
class OverlaySourceCard extends StatelessWidget {
  const OverlaySourceCard({
    required this.scenes,
    required this.workspace,
    super.key,
  });
  final OverlaySceneController scenes;
  final OverlayWorkspaceModule workspace;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([scenes.projection, workspace.projection]),
    builder: (context, _) => _card(context, scenes.projection.value),
  );

  Widget _card(BuildContext context, OverlaySceneState state) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final view = projectOverlayScene(state);
    final fixed = state.presetBindingId != null;
    String label(String? id) {
      final option = view.optionById(id);
      return option == null
          ? '—'
          : overlaySourceOptionLabel(view, option, strings);
    }

    final choices = view.options.where(
      (option) =>
          option.id == 'auto' ||
          option.id == 'room' ||
          option.id == 'fleet' ||
          option.id.startsWith('org:'),
    );
    final actual = state.actualId == null ? null : label(state.actualId);
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: tokens.space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              strings.text('overlay.source.cardTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            OverlaySettingsHelp(strings.text('overlay.source.displayOnly')),
          ],
        ),
        SizedBox(height: tokens.space.sm),
        Wrap(
          spacing: tokens.space.xs,
          runSpacing: tokens.space.xs,
          children: [
            for (final option in choices)
              StarBridgeChoiceChip(
                key: Key('overlay-source-card-${option.id}'),
                controlKey: Key('overlay-source-card-${option.id}-command'),
                label: option.id == 'auto' && !fixed && actual != null
                    ? strings
                          .text('overlay.source.autoNow')
                          .replaceAll('{source}', actual)
                    : label(option.id),
                selected: !fixed && view.preferredSceneId == option.id,
                onSelected: option.enabled && view.canChange
                    ? (_) => unawaited(scenes.select(option.id))
                    : null,
              ),
          ],
        ),
        SizedBox(height: tokens.space.sm),
        Wrap(
          spacing: tokens.space.sm,
          runSpacing: tokens.space.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              strings.text('overlay.source.nowShowing'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              key: const Key('overlay-source-card-actual'),
              fixed
                  ? strings
                        .text('overlay.source.planFixedLabel')
                        .replaceAll('{source}', label(state.presetBindingId))
                  : actual ?? '—',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              key: const Key('overlay-source-card-reason'),
              strings.text(_reasonKey(state, view.fallbackReasonKey)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                // Only a real problem is warning colored; a plan-fixed source
                // is the user's own setting.
                color:
                    !fixed &&
                        view.fallbackReasonKey == 'overlay.source.unavailable'
                    ? tokens.colors.warning
                    : tokens.colors.textSecondary,
              ),
            ),
          ],
        ),
        if (fixed) ...[
          SizedBox(height: tokens.space.sm),
          StarBridgeActionButton(
            controlKey: const Key('overlay-source-card-follow'),
            onActivate: view.canChange
                ? (_) => unawaited(scenes.select('followShared'))
                : null,
            child: Text(strings.text('overlay.source.followShared')),
          ),
        ],
      ],
    );
    final aside = _Overrides(
      workspace: workspace,
      targetName: (binding) => switch (binding.mode) {
        OverlaySourceMode.auto => strings.text('overlay.source.auto'),
        OverlaySourceMode.room => strings.text('overlay.source.room'),
        OverlaySourceMode.fleet => state.fleetLabel(strings.text),
        OverlaySourceMode.community =>
          state.targets
                  .where((t) => t.code == binding.communityCode)
                  .firstOrNull
                  ?.name ??
              strings.text('overlay.source.missing'),
        OverlaySourceMode.none => '',
      },
    );
    return StarBridgeSurface(
      key: const Key('overlay-source-card'),
      role: SurfaceRole.panel,
      padding: EdgeInsets.all(tokens.space.md),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 860
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: main),
                  SizedBox(width: tokens.space.lg),
                  SizedBox(width: 280, child: aside),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  main,
                  SizedBox(height: tokens.space.md),
                  aside,
                ],
              ),
      ),
    );
  }

  static String _reasonKey(OverlaySceneState state, String? fallback) {
    if (state.presetBindingId != null) return 'overlay.source.planFixedHint';
    if (fallback != null) return fallback;
    if (state.preferredId != 'auto') return 'overlay.source.why.fixed';
    return switch (state.actualId) {
      'room' => 'overlay.source.why.autoRoom',
      'local' || null => 'overlay.source.why.autoLocal',
      _ => 'overlay.source.why.autoOrg',
    };
  }
}

/// Modules that show something other than the shared choice. Always listed,
/// so a per-module source is never a hidden exception.
class _Overrides extends StatelessWidget {
  const _Overrides({required this.workspace, required this.targetName});
  final OverlayWorkspaceModule workspace;
  final String Function(OverlaySourceBinding binding) targetName;

  static const _groups = {
    OverlaySourceModule.notice: 'notice',
    OverlaySourceModule.overview: 'fleetOverview',
    OverlaySourceModule.members: 'members',
    OverlaySourceModule.chat: 'chat',
    OverlaySourceModule.events: 'events',
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final sources = workspace.projection.value.sources;
    final rows = <String>[
      if (sources != null)
        for (final module in OverlaySourceModule.values)
          if (module == OverlaySourceModule.chat &&
              sources.chatSources.isNotEmpty)
            '${strings.text('overlay.workspace.group.chat')} → ${strings.text('overlay.source.chatMultiple')}'
          else if (sources.forModule(module).mode != OverlaySourceMode.none)
            '${strings.text('overlay.workspace.group.${_groups[module]}')} → ${targetName(sources.forModule(module))}',
    ];
    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      key: const Key('overlay-source-card-overrides'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.isEmpty)
          OverlaySettingsHelp(strings.text('overlay.source.overridesNone'))
        else ...[
          Text(
            strings
                .text('overlay.source.overrides')
                .replaceAll('{count}', '${rows.length}'),
            style: style?.copyWith(color: tokens.colors.warning),
          ),
          for (final row in rows) Text(row, style: style),
          SizedBox(height: tokens.space.xs),
          StarBridgeActionButton(
            controlKey: const Key('overlay-source-card-clear-overrides'),
            onActivate: workspace.projection.value.busy
                ? null
                : (_) => workspace.followSharedSourceInModules(),
            child: Text(strings.text('overlay.source.clearOverrides')),
          ),
        ],
        SizedBox(height: tokens.space.sm),
        OverlaySettingsHelp(strings.text('overlay.source.inGameHint')),
      ],
    );
  }
}
