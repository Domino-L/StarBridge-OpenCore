import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/color_choice_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_preset_sources.dart';
import 'overlay_scene_controller.dart';

/// Reuses the account directory. It has no timer, network reader or permission cache.
class OverlaySourceBindingField extends StatelessWidget {
  const OverlaySourceBindingField({
    required this.value,
    required this.onChanged,
    this.scenes,
    this.presetBinding = false,
    super.key,
  });
  final OverlaySourceBinding value;
  final ValueChanged<OverlaySourceBinding>? onChanged;
  final OverlaySceneController? scenes;
  final bool presetBinding;

  @override
  Widget build(BuildContext context) => scenes == null
      ? _build(context, const OverlaySceneState())
      : ValueListenableBuilder<OverlaySceneState>(
          valueListenable: scenes!.projection,
          builder: (context, state, _) => _build(context, state),
        );

  /// What "follow" shows right now: the plan's fixed source, else the shared
  /// choice as resolved by the Host.
  static String _shared(OverlaySceneState state, String Function(String) copy) {
    final id =
        state.presetBindingId ?? state.actualId ?? state.accountPreferredId;
    if (id.startsWith('org:')) {
      return state.targets
              .where((t) => 'org:${t.code}' == id)
              .firstOrNull
              ?.name ??
          copy('overlay.source.missing');
    }
    if (id == 'fleet') return state.fleetLabel(copy);
    return copy(switch (id) {
      'room' => 'overlay.source.room',
      'local' => 'overlay.source.localName',
      _ => 'overlay.source.auto',
    });
  }

  Widget _build(BuildContext context, OverlaySceneState state) {
    final copy = AppStrings.of(context).text;
    final field = copy(
      presetBinding ? 'overlay.source.planField' : 'overlay.source.moduleField',
    );
    final entries = <OverlaySourceBinding, String>{
      const OverlaySourceBinding.follow(): presetBinding
          ? copy('overlay.source.planNotFixed')
          : copy('overlay.source.followAbove')
                .replaceAll('{source}', _shared(state, copy)),
      const OverlaySourceBinding.automatic(): copy('overlay.source.auto'),
      const OverlaySourceBinding.room(): copy('overlay.source.room'),
      if (state.offersFleet)
        const OverlaySourceBinding.fleet(): state.fleetLabel(copy),
      if (state.available && !state.failure && state.sourceOwnerKey != null)
        for (final target in state.targets)
          OverlaySourceBinding.community(target.code, state.sourceOwnerKey!):
              target.name,
    };
    final missing = !entries.containsKey(value);
    if (missing) entries[value] = copy('overlay.source.missing');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StarBridgeMenuAnchor(
          // Never retain an open directory across account/context invalidation.
          // Binding identity includes its owner; normal directory updates use
          // the menu's latest-entry lookup rather than an old captured callback.
          key: ValueKey((
            state.sourceOwnerKey,
            state.contextGeneration,
            state.available,
            state.failure,
          )),
          enabled: onChanged != null,
          semanticLabel: '$field · ${entries[value]}',
          entries: [
            for (final entry in entries.entries)
              StarBridgeMenuEntry(
                id: entry.key,
                label: entry.value,
                selected: entry.key == value,
                onActivate: onChanged == null || (missing && entry.key == value)
                    ? null
                    : (_) => onChanged!(entry.key),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        child: entry.key == value
                            ? const ColorChoiceIcon.selection(
                                selected: true,
                                size: 16,
                              )
                            : null,
                      ),
                      Flexible(
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          builder: (context, controller, focus, toggle) => StarBridgeActionRow(
            controlKey: const Key('overlay-source-binding-trigger'),
            focusNode: focus,
            semanticLabel: '$field · ${entries[value]}',
            onActivate: onChanged == null
                ? null
                : (_, source) => toggle(source),
            child: ExcludeSemantics(
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: field,
                  isDense: true,
                  enabled: onChanged != null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entries[value]!,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const StarBridgeIcon(
                      StarBridgeIconSemantic.menuDown,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: context.tokens.space.xs),
        Text(
          copy(
            missing
                ? presetBinding
                      ? 'overlay.source.bindingUnavailable'
                      : 'overlay.source.moduleUnavailable'
                : presetBinding
                ? 'overlay.source.displayOnly'
                : value.mode == OverlaySourceMode.none
                ? 'overlay.source.moduleFollowHelp'
                : 'overlay.source.moduleOwnHelp',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            // A module with its own source is the exception worth noticing.
            color: !presetBinding && value.mode != OverlaySourceMode.none
                ? context.tokens.colors.warning
                : null,
          ),
        ),
      ],
    );
  }
}
