import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/preferences/app_preferences.dart';
import '../../app/routing/exit_application_intent.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_segmented_control.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_action_button.dart';

class GeneralSettingsBehavior extends StatelessWidget {
  const GeneralSettingsBehavior({
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final ApplicationBehaviorPreferences value;
  final bool enabled;
  final Future<bool> Function(ApplicationBehaviorPreferences value) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final normalized = value.normalize();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BehaviorRow(
          title: strings.text('settings.general.behavior.launch.title'),
          description: strings.text(
            'settings.general.behavior.launch.description',
          ),
          control: StarBridgeSwitch(
            controlKey: const Key('general-launch-at-startup'),
            label: strings.text('settings.general.behavior.launch.title'),
            value: normalized.launchAtStartup,
            onChanged: enabled
                ? (selected) => onChanged(
                    normalized
                        .copyWith(
                          launchAtStartup: selected,
                          startMinimized: normalized.startupChoiceMade
                              ? normalized.startMinimized
                              : selected,
                          startupChoiceMade: true,
                        )
                        .normalize(),
                  )
                : null,
          ),
        ),
        Divider(height: tokens.space.lg),
        _BehaviorRow(
          title: strings.text('settings.general.behavior.close.title'),
          description: strings.text(
            'settings.general.behavior.close.description',
          ),
          control: StarBridgeSegmentedControl<bool>(
            controlKey: const Key('general-close-behavior'),
            segments: [
              StarBridgeSegment(
                value: true,
                label: strings.text('settings.general.behavior.close.tray'),
              ),
              StarBridgeSegment(
                value: false,
                label: strings.text('settings.general.behavior.close.exit'),
              ),
            ],
            value: normalized.keepRunningInBackground,
            onChanged: enabled
                ? (selection) => onChanged(
                    normalized.copyWith(
                      keepRunningInBackground: selection,
                      closeBehaviorChoiceMade: true,
                    ),
                  )
                : null,
          ),
        ),
        Divider(height: tokens.space.lg),
        _BehaviorRow(
          title: strings.text('settings.general.behavior.startup.title'),
          description: strings.text(
            'settings.general.behavior.startup.description',
          ),
          control: StarBridgeSegmentedControl<bool>(
            controlKey: const Key('general-startup-behavior'),
            segments: [
              StarBridgeSegment(
                value: false,
                label: strings.text('settings.general.behavior.startup.window'),
              ),
              StarBridgeSegment(
                value: true,
                label: strings.text(
                  'settings.general.behavior.startup.background',
                ),
              ),
            ],
            value: normalized.startMinimized,
            onChanged: enabled && normalized.launchAtStartup
                ? (selection) => onChanged(
                    normalized.copyWith(
                      startMinimized: selection,
                      startupChoiceMade: true,
                    ),
                  )
                : null,
          ),
        ),
        SizedBox(height: tokens.space.sm),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: StarBridgeActionButton(
            controlKey: const Key('general-exit-application'),
            onActivate:
                Actions.maybeFind<ExitApplicationIntent>(context) == null
                ? null
                : (source) => Actions.invoke(
                    context,
                    ExitApplicationIntent(source: source),
                  ),
            child: Text(strings.text('settings.general.behavior.close.exit')),
          ),
        ),
      ],
    );
  }
}

class _BehaviorRow extends StatelessWidget {
  const _BehaviorRow({
    required this.title,
    required this.description,
    required this.control,
  });

  final String title;
  final String description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: tokens.space.xxs),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              copy,
              SizedBox(height: tokens.space.sm),
              Align(alignment: AlignmentDirectional.centerEnd, child: control),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: copy),
            SizedBox(width: tokens.space.lg),
            control,
          ],
        );
      },
    );
  }
}
