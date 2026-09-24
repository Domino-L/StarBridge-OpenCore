import '../../design_system/icons/standard_icon.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'settings_capability_catalog.dart';
import 'settings_models.dart';
import 'settings_entry_catalog.dart';
import 'settings_entry_dialog.dart';

class PlannedSettingsCapabilities extends StatelessWidget {
  const PlannedSettingsCapabilities({
    required this.section,
    this.capabilityIds,
    this.title,
    this.showIntro = true,
    super.key,
  });

  final SettingsSection section;
  final Set<String>? capabilityIds;
  final String? title;
  final bool showIntro;

  @override
  Widget build(BuildContext context) {
    final capabilities = SettingsCapabilityCatalog.plannedFor(section)
        .where(
          (item) => capabilityIds == null || capabilityIds!.contains(item.id),
        )
        .toList(growable: false);
    if (capabilities.isEmpty) {
      return const SizedBox.shrink();
    }

    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: Key(
        'settings-planned-capabilities-${section.name}${capabilityIds == null ? '' : '-${capabilityIds!.join('-')}'}',
      ),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarBridgeIcon(
                section.icon,
                size: tokens.icons.medium,
                color: tokens.colors.textSecondary,
              ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? settingsEntryText(strings, 'title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (showIntro &&
                        section != SettingsSection.accountIdentity) ...[
                      SizedBox(height: tokens.space.xxs),
                      Text(
                        settingsEntryText(strings, 'intro'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: tokens.space.sm),
              if (!capabilities.any(
                (item) =>
                    SettingsEntryOverrides.of(context).containsKey(item.id),
              ))
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.space.sm,
                    vertical: tokens.space.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surfaces.ground.fill,
                    border: Border.all(
                      color: tokens.surfaces.raised.border,
                      width: tokens.stroke.regular,
                    ),
                    borderRadius: tokens.shape.small,
                  ),
                  child: Text(
                    settingsEntryText(strings, 'unavailable'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          SizedBox(height: tokens.space.md),
          for (var index = 0; index < capabilities.length; index++) ...[
            if (index > 0)
              Divider(
                height: tokens.space.lg,
                color: tokens.surfaces.raised.border,
              ),
            _CapabilityRow(capability: capabilities[index]),
          ],
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.capability});

  final SettingsCapabilityDefinition capability;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('settings-capability-${capability.id}'),
        borderRadius: tokens.shape.small,
        onTap: () => showSettingsCapabilityEntry(context, capability),
        child: Padding(
          padding: EdgeInsets.all(tokens.space.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text(capability.titleKey),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      settingsEntryText(
                        strings,
                        'description.${capability.id}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.space.sm),
              const StandardIcon(StandardIconSemantic.chevronRight, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
