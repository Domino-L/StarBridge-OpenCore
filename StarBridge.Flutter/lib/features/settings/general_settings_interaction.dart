import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/preferences/app_preferences.dart';
import '../../design_system/interaction/starbridge_segmented_control.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/release/official_client_profile.dart';

class GeneralSettingsInteraction extends StatelessWidget {
  const GeneralSettingsInteraction({
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });
  final InteractionStyle value;
  final bool enabled;
  final Future<bool> Function(InteractionStyle value) onChanged;

  @override
  Widget build(BuildContext context) {
    if (!OfficialClientProfile.advancedInteractions) {
      return const SizedBox.shrink();
    }
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.text('settings.general.interaction.title'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: context.tokens.space.xs),
        Text(
          strings.text('settings.general.interaction.description'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(height: context.tokens.space.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final segments = [
              for (final style in InteractionStyle.values)
                StarBridgeSegment(
                  value: style,
                  label: strings.text(
                    'settings.general.interaction.${style.name}',
                  ),
                ),
            ];
            final labelSize = MediaQuery.textScalerOf(context)
                .scale(Theme.of(context).textTheme.labelLarge?.fontSize ?? 14);
            final minimum =
                segments.fold<int>(0, (sum, s) => sum + s.label.runes.length) *
                    labelSize +
                160;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: constraints.maxWidth > minimum
                    ? constraints.maxWidth
                    : minimum,
                child: StarBridgeSegmentedControl<InteractionStyle>(
                  controlKey: const Key('general-interaction-style'),
                  value: value,
                  segments: segments,
                  onChanged: enabled ? (style) => onChanged(style) : null,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
