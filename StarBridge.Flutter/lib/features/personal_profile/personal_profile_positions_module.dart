import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_models.dart';
import 'personal_profile_module_surface.dart';
import 'personal_profile_tags_module.dart';

class PersonalProfilePositionsModule extends StatelessWidget {
  const PersonalProfilePositionsModule({
    required this.roles,
    required this.participationInterests,
    required this.supportCapabilities,
    this.headerTrailing,
    super.key,
  });

  final List<PersonalProfileTagValue> roles;
  final List<PersonalProfileTagValue> participationInterests;
  final List<PersonalProfileTagValue> supportCapabilities;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return PersonalProfileModuleSurface(
      icon: StarBridgeIconSemantic.operation,
      titleKey: 'profile.position.title',
      accentRole: DomainColorRole.command,
      headerTrailing: headerTrailing,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: _TagSection(titleKey: 'profile.roles.title', values: roles),
          ),
          VerticalDivider(
            width: tokens.space.lg,
            thickness: tokens.stroke.hairline,
            color: tokens.surfaces.panel.border,
          ),
          Expanded(
            flex: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _TagSection(
                    titleKey: 'profile.participation.title',
                    values: participationInterests,
                  ),
                ),
                SizedBox(width: tokens.space.sm),
                Expanded(
                  child: _TagSection(
                    titleKey: 'profile.support.title',
                    values: supportCapabilities,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagSection extends StatelessWidget {
  const _TagSection({required this.titleKey, required this.values});

  final String titleKey;
  final List<PersonalProfileTagValue> values;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.of(context).text(titleKey),
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(height: tokens.space.xs),
        Expanded(
          child: SingleChildScrollView(
            child: PersonalProfileTagWrap(values: values),
          ),
        ),
      ],
    );
  }
}
