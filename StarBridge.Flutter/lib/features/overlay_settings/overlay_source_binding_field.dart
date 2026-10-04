import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
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

  Widget _build(BuildContext context, OverlaySceneState state) {
    final copy = AppStrings.of(context).text;
    final entries = <OverlaySourceBinding, String>{
      const OverlaySourceBinding.follow(): copy(
        presetBinding
            ? 'overlay.source.followAccount'
            : 'overlay.source.followPreset',
      ),
      const OverlaySourceBinding.automatic(): copy('overlay.source.auto'),
      const OverlaySourceBinding.room(): copy('overlay.source.room'),
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
        InputDecorator(
          decoration: InputDecoration(
            labelText: copy('overlay.source.title'),
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<OverlaySourceBinding>(
              value: value,
              isExpanded: true,
              isDense: true,
              items: entries.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      enabled: !(missing && entry.key == value),
                      child: Text(
                        entry.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged == null
                  ? null
                  : (value) {
                      if (value != null) onChanged!(value);
                    },
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
                : 'overlay.source.displayOnly',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
