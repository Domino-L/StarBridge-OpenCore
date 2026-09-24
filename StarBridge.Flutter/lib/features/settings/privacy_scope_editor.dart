import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

enum PrivacyScopeTone { room, officialFleet, organization }

@immutable
final class PrivacyFieldChoice {
  const PrivacyFieldChoice({
    required this.id,
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final String id;
  final StarBridgeIconSemantic icon;
  final String label;
  final String description;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;
}

@immutable
final class PrivacyAudienceChoice {
  const PrivacyAudienceChoice({
    required this.id,
    required this.label,
    required this.description,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final String id;
  final String label;
  final String description;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;
}

class PrivacyAudienceEditor extends StatelessWidget {
  const PrivacyAudienceEditor({
    required this.scopeKey,
    required this.label,
    required this.choices,
    super.key,
  });

  final String scopeKey;
  final String label;
  final List<PrivacyAudienceChoice> choices;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: tokens.colors.textSecondary),
        ),
        SizedBox(height: tokens.space.xs),
        for (var index = 0; index < choices.length; index++) ...[
          if (index > 0)
            Divider(
              height: tokens.stroke.hairline,
              color: tokens.surfaces.raised.border,
            ),
          _PrivacyAudienceRow(scopeKey: scopeKey, choice: choices[index]),
        ],
      ],
    );
  }
}

class PrivacyScopeEditor extends StatelessWidget {
  const PrivacyScopeEditor({
    required this.scopeKey,
    required this.tone,
    required this.icon,
    required this.title,
    required this.description,
    required this.fieldsLabel,
    required this.fields,
    this.badge,
    this.status,
    this.statusPending = false,
    this.audience,
    this.leading,
    super.key,
  });

  final String scopeKey;
  final PrivacyScopeTone tone;
  final StarBridgeIconSemantic icon;
  final String title;
  final String description;
  final String fieldsLabel;
  final List<PrivacyFieldChoice> fields;
  final String? badge;
  final String? status;
  final bool statusPending;
  final Widget? audience;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = _resolveTone(tokens, tone);
    return StarBridgeSurface(
      key: Key('privacy-scope-$scopeKey'),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading ??
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.soft,
                      borderRadius: tokens.shape.small,
                    ),
                    alignment: Alignment.center,
                    child: StarBridgeIcon(
                      icon,
                      size: tokens.icons.medium,
                      color: colors.foreground,
                    ),
                  ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: tokens.space.sm,
                      runSpacing: tokens.space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (badge case final badge?)
                          _ScopeBadge(
                            label: badge,
                            foreground: colors.foreground,
                            background: colors.soft,
                          ),
                        if (status case final status?)
                          _ScopeBadge(
                            key: Key('privacy-scope-$scopeKey-status'),
                            label: status,
                            foreground: statusPending
                                ? tokens.colors.warning
                                : tokens.colors.textSecondary,
                            background: statusPending
                                ? tokens.colors.warningSoft
                                : tokens.surfaces.raised.fill,
                          ),
                      ],
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (audience case final audience?) ...[
            SizedBox(height: tokens.space.md),
            audience,
          ],
          SizedBox(height: tokens.space.md),
          Text(
            fieldsLabel,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.sm),
          _PrivacyFieldGrid(scopeKey: scopeKey, fields: fields, colors: colors),
        ],
      ),
    );
  }
}

class _PrivacyFieldGrid extends StatelessWidget {
  const _PrivacyFieldGrid({
    required this.scopeKey,
    required this.fields,
    required this.colors,
  });

  final String scopeKey;
  final List<PrivacyFieldChoice> fields;
  final DomainColorPairTokens colors;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep labels and a real switch on one line at normal text sizes;
        // use fewer columns when accessibility text scaling needs more room.
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = constraints.maxWidth >= 880 * scale
            ? 4
            : constraints.maxWidth >= 440 * scale
            ? 2
            : 1;
        final gap = tokens.space.sm;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final field in fields)
              SizedBox(
                width: width,
                child: _PrivacyFieldTile(
                  scopeKey: scopeKey,
                  field: field,
                  colors: colors,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PrivacyAudienceRow extends StatelessWidget {
  const _PrivacyAudienceRow({required this.scopeKey, required this.choice});

  final String scopeKey;
  final PrivacyAudienceChoice choice;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      key: Key('privacy-scope-$scopeKey-audience-${choice.id}'),
      onTap: choice.enabled ? () => choice.onChanged(!choice.selected) : null,
      borderRadius: tokens.shape.small,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: choice.selected,
              onChanged: choice.enabled
                  ? (value) => choice.onChanged(value ?? false)
                  : null,
            ),
            SizedBox(width: tokens.space.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    choice.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: choice.enabled
                          ? tokens.colors.textPrimary
                          : tokens.colors.textDisabled,
                    ),
                  ),
                  SizedBox(height: tokens.space.xxs),
                  Text(
                    choice.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: choice.enabled
                          ? tokens.colors.textSecondary
                          : tokens.colors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyFieldTile extends StatelessWidget {
  const _PrivacyFieldTile({
    required this.scopeKey,
    required this.field,
    required this.colors,
  });

  final String scopeKey;
  final PrivacyFieldChoice field;
  final DomainColorPairTokens colors;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selected = field.selected;
    final enabled = field.enabled;
    final foreground = enabled
        ? selected
              ? colors.foreground
              : tokens.colors.textSecondary
        : tokens.colors.textDisabled;
    return Tooltip(
      message: field.description,
      child: MergeSemantics(
        child: InkWell(
          key: Key('privacy-scope-$scopeKey-field-${field.id}'),
          onTap: enabled ? () => field.onChanged(!selected) : null,
          // The switch owns keyboard focus; the whole row remains clickable.
          canRequestFocus: false,
          borderRadius: tokens.shape.small,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                StarBridgeIcon(
                  field.icon,
                  size: tokens.icons.medium,
                  color: foreground,
                ),
                SizedBox(width: tokens.space.sm),
                Expanded(
                  child: Text(
                    field.label,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: foreground),
                  ),
                ),
                Switch(
                  key: Key('privacy-scope-$scopeKey-switch-${field.id}'),
                  value: selected,
                  activeTrackColor: colors.foreground,
                  onChanged: enabled ? field.onChanged : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({
    required this.label,
    required this.foreground,
    required this.background,
    super.key,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: tokens.shape.small,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground),
      ),
    );
  }
}

DomainColorPairTokens _resolveTone(
  StarBridgeTokens tokens,
  PrivacyScopeTone tone,
) => switch (tone) {
  PrivacyScopeTone.room => DomainColorPairTokens(
    foreground: tokens.colors.info,
    soft: tokens.colors.infoSoft,
  ),
  PrivacyScopeTone.officialFleet => tokens.domainColors.command,
  PrivacyScopeTone.organization => tokens.domainColors.recon,
};
