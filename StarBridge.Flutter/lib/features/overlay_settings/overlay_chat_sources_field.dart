import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'overlay_preset_sources.dart';
import 'overlay_scene_controller.dart';
import 'overlay_source_binding_field.dart';

/// Local display intent only; the Host validates membership and the shared budget.
class OverlayChatSourcesField extends StatelessWidget {
  const OverlayChatSourcesField({
    required this.value,
    required this.onChanged,
    required this.onSingleChanged,
    this.scenes,
    super.key,
  });
  final OverlayPresetSources value;
  final ValueChanged<List<OverlaySourceBinding>>? onChanged;
  final ValueChanged<OverlaySourceBinding>? onSingleChanged;
  final OverlaySceneController? scenes;

  String _name(
    BuildContext context,
    OverlaySourceBinding source,
    OverlaySceneState state,
  ) {
    final copy = AppStrings.of(context).text;
    if (source.mode == OverlaySourceMode.room) {
      return copy('overlay.source.room');
    }
    if (source.mode == OverlaySourceMode.fleet) {
      return state.offersFleet
          ? state.fleetLabel(copy)
          : copy('overlay.source.missing');
    }
    final target = source.ownerKey == state.sourceOwnerKey
        ? state.targets.where((t) => t.code == source.communityCode).firstOrNull
        : null;
    return target == null
        ? copy('overlay.source.missing')
        : '${copy('overlay.source.organization')} · ${target.name}';
  }

  @override
  Widget build(BuildContext context) => scenes == null
      ? _build(context, const OverlaySceneState())
      : ValueListenableBuilder(
          valueListenable: scenes!.projection,
          builder: (context, state, _) => _build(context, state),
        );

  Widget _build(BuildContext context, OverlaySceneState state) {
    final copy = AppStrings.of(context).text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value.chatSources.isEmpty)
          OverlaySourceBindingField(
            value: value.forModule(OverlaySourceModule.chat),
            scenes: scenes,
            onChanged: onSingleChanged,
          )
        else ...[
          Text(
            copy('overlay.source.chatSelection')
                .replaceAll('{count}', '${value.chatSources.length}'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final source in value.chatSources)
                Chip(label: Text(_name(context, source, state))),
            ],
          ),
          Text(
            copy('overlay.source.displayOnly'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        StarBridgeActionButton(
          key: const Key('overlay-chat-select-sources'),
          onActivate: onChanged == null
              ? null
              : (source) => _select(context, state, source),
          child: Text(copy('overlay.source.selectChat')),
        ),
        if (value.chatSources.isNotEmpty)
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            onActivate: onChanged == null ? null : (_) => onChanged!([]),
            child: Text(copy('overlay.source.singleChat')),
          ),
      ],
    );
  }

  Future<void> _select(
    BuildContext context,
    OverlaySceneState initial,
    InteractionSource source,
  ) async {
    final copy = AppStrings.of(context).text;
    final selected = value.chatSources.toSet();
    final previous = value.forModule(OverlaySourceModule.chat);
    if (selected.isEmpty && previous.isConcrete) {
      selected.add(previous);
    }
    final result = await showStarBridgeDialog<List<OverlaySourceBinding>>(
      context,
      source: source,
      builder: (context) {
        Widget dialog(OverlaySceneState state) => StatefulBuilder(
          builder: (context, update) {
            final current =
                state.sourceOwnerKey == initial.sourceOwnerKey &&
                state.contextGeneration == initial.contextGeneration;
            final available = <OverlaySourceBinding>{
              const OverlaySourceBinding.room(),
              if (state.offersFleet) const OverlaySourceBinding.fleet(),
              if (state.available &&
                  !state.failure &&
                  state.sourceOwnerKey != null)
                for (final target in state.targets)
                  OverlaySourceBinding.community(
                    target.code,
                    state.sourceOwnerKey!,
                  ),
            };
            final options = {...available, ...selected};
            return AlertDialog(
              title: Text(copy('overlay.source.selectChat')),
              scrollable: true,
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      copy(
                        current
                            ? 'overlay.source.chatHelp'
                            : 'overlay.source.changedAccount',
                      ),
                    ),
                    if (current) ...[
                      const SizedBox(height: 8),
                      Text(
                        copy('overlay.source.chatSelection')
                            .replaceAll('{count}', '${selected.length}'),
                      ),
                      for (final source in options)
                        StarBridgeCheckboxTile(
                          key: ValueKey(source),
                          value: selected.contains(source),
                          label: _name(context, source, state),
                          onChanged:
                              !selected.contains(source) &&
                                  (selected.length >= 8 ||
                                      !available.contains(source))
                              ? null
                              : (checked) => update(() {
                                  checked == true
                                      ? selected.add(source)
                                      : selected.remove(source);
                                }),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (source) =>
                      dismissStarBridgeDialog<List<OverlaySourceBinding>>(
                        context,
                        source: source,
                      ),
                  child: Text(copy('overlay.source.cancelChat')),
                ),
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.primary,
                  onActivate: !current || selected.isEmpty
                      ? null
                      : (source) => dismissStarBridgeDialog(
                          context,
                          source: source,
                          result: selected.toList(),
                        ),
                  child: Text(copy('overlay.source.applyChat')),
                ),
              ],
            );
          },
        );
        return scenes == null
            ? dialog(initial)
            : ValueListenableBuilder(
                valueListenable: scenes!.projection,
                builder: (_, state, _) => dialog(state),
              );
      },
    );
    final latest = scenes?.projection.value ?? initial;
    if (result != null &&
        context.mounted &&
        latest.sourceOwnerKey == initial.sourceOwnerKey &&
        latest.contextGeneration == initial.contextGeneration) {
      onChanged?.call(result);
    }
  }
}
