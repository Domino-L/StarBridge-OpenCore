import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'personal_profile_domain_colors.dart';
import 'personal_profile_models.dart';
import 'personal_profile_module_surface.dart';

class PersonalProfileTagsModule extends StatelessWidget {
  const PersonalProfileTagsModule({
    required this.titleKey,
    required this.values,
    this.icon = StarBridgeIconSemantic.operation,
    super.key,
  });

  final String titleKey;
  final List<PersonalProfileTagValue> values;
  final StarBridgeIconSemantic icon;

  @override
  Widget build(BuildContext context) {
    return PersonalProfileModuleSurface(
      icon: icon,
      titleKey: titleKey,
      child: PersonalProfileTagWrap(values: values),
    );
  }
}

class PersonalProfileTagWrap extends StatelessWidget {
  const PersonalProfileTagWrap({required this.values, super.key});

  final List<PersonalProfileTagValue> values;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Wrap(
      spacing: tokens.space.xs,
      runSpacing: tokens.space.xs,
      children: [
        for (final value in values)
          _ProfileTag(
            key: Key('profile-tag-${value.labelKey}'),
            label: value.displayLabel ?? strings.text(value.labelKey),
            category: value.category,
            isPrimary: value.isPrimary,
          ),
      ],
    );
  }
}

class _ProfileTag extends StatelessWidget {
  const _ProfileTag({
    required this.label,
    required this.category,
    required this.isPrimary,
    super.key,
  });

  final String label;
  final PersonalProfileTagCategory category;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = tokens.domainColors.resolve(category.domainColorRole);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        color: colors.soft,
        borderRadius: tokens.shape.small,
        border: Border.all(
          color: colors.foreground,
          width: isPrimary ? tokens.stroke.strong : tokens.stroke.hairline,
        ),
      ),
      child: Text(
        isPrimary
            ? '$label · ${AppStrings.of(context).text('profile.role.primary')}'
            : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.foreground,
          fontWeight: isPrimary ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}
