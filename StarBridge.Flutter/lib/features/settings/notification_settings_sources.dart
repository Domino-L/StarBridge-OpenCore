import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'notification_settings_common.dart';
import 'notification_settings_models.dart';
import '../communities/community_logo.dart';

class NotificationSourceRulesPanel extends StatelessWidget {
  const NotificationSourceRulesPanel({
    required this.settings,
    required this.enabled,
    required this.onSave,
    super.key,
  });

  final NotificationSettingsValue settings;
  final bool enabled;
  final Future<bool> Function(NotificationSettingsValue settings) onSave;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return NotificationSettingsPanel(
      key: const Key('notification-source-rules-panel'),
      icon: StarBridgeIconSemantic.officialFleet,
      titleKey: 'settings.notification.sources.title',
      descriptionKey: 'settings.notification.sources.description',
      accentColor: tokens.domainColors
          .resolve(DomainColorRole.command)
          .foreground,
      trailing: _SourceCount(count: settings.sourceRules.length),
      child: settings.sourceRules.isEmpty
          ? const _EmptySources()
          : Column(
              children: [
                for (
                  var index = 0;
                  index < settings.sourceRules.length;
                  index++
                )
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == settings.sourceRules.length - 1
                          ? 0
                          : tokens.space.xs,
                    ),
                    child: NotificationSourceRuleRow(
                      rule: settings.sourceRules[index],
                      enabled: enabled,
                      onChanged: (mode) => onSave(
                        settings.updateSourceMode(
                          settings.sourceRules[index].sourceRef,
                          mode,
                        ),
                      ),
                    ),
                  ),
                SizedBox(height: tokens.space.sm),
                const _NoGlobalDndNote(),
              ],
            ),
    );
  }
}

class NotificationSourceRuleRow extends StatelessWidget {
  const NotificationSourceRuleRow({
    super.key,
    required this.rule,
    required this.enabled,
    required this.onChanged,
  });

  final NotificationSourceRule rule;
  final bool enabled;
  final Future<bool> Function(NotificationSourceMode mode) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final color = _sourceColor(context, rule.kind);
    return Container(
      padding: EdgeInsets.all(tokens.space.sm),
      decoration: BoxDecoration(
        color: tokens.surfaces.ground.fill,
        border: Border.all(
          color: tokens.surfaces.panel.border,
          width: tokens.stroke.hairline,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Row(
            children: [
              if (rule.kind == NotificationSourceKind.community)
                CommunityLogo(data: rule.logoImageData, size: 36, framed: false)
              else
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: tokens.shape.small,
                  ),
                  child: StarBridgeIcon(
                    _sourceIcon(rule.kind),
                    size: tokens.icons.medium,
                    color: color,
                  ),
                ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      rule.contextLabel.isEmpty
                          ? strings.text(_sourceKindKey(rule.kind))
                          : '${strings.text(_sourceKindKey(rule.kind))} · ${rule.contextLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          );
          final selector = _SourceModeSelector(
            sourceRef: rule.sourceRef,
            value: rule.mode,
            enabled: enabled,
            onChanged: onChanged,
          );
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                SizedBox(height: tokens.space.sm),
                selector,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              SizedBox(width: tokens.space.md),
              SizedBox(width: 430, child: selector),
            ],
          );
        },
      ),
    );
  }
}

class _SourceModeSelector extends StatelessWidget {
  const _SourceModeSelector({
    required this.sourceRef,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String sourceRef;
  final NotificationSourceMode value;
  final bool enabled;
  final Future<bool> Function(NotificationSourceMode mode) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 390) {
          return DropdownButtonFormField<NotificationSourceMode>(
            key: ValueKey(('notification-source-mode-$sourceRef', value)),
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: strings.text('settings.notification.sources.mode'),
            ),
            items: [
              for (final mode in NotificationSourceMode.values)
                DropdownMenuItem(
                  value: mode,
                  child: Text(strings.text(_sourceModeKey(mode))),
                ),
            ],
            onChanged: enabled
                ? (next) {
                    if (next != null && next != value) {
                      onChanged(next);
                    }
                  }
                : null,
          );
        }
        return SegmentedButton<NotificationSourceMode>(
          key: Key('notification-source-mode-$sourceRef'),
          segments: [
            for (final mode in NotificationSourceMode.values)
              ButtonSegment(
                value: mode,
                icon: StarBridgeIcon(
                  _sourceModeIcon(mode),
                  size: context.tokens.icons.small,
                ),
                label: Text(strings.text(_sourceModeKey(mode))),
              ),
          ],
          selected: {value},
          onSelectionChanged: enabled
              ? (selection) {
                  final next = selection.first;
                  if (next != value) {
                    onChanged(next);
                  }
                }
              : null,
          showSelectedIcon: false,
        );
      },
    );
  }
}

class _SourceCount extends StatelessWidget {
  const _SourceCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaces.ground.fill,
        border: Border.all(
          color: tokens.surfaces.panel.border,
          width: tokens.stroke.hairline,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Text(
        strings
            .text('settings.notification.sources.count')
            .replaceAll('{count}', count.toString()),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _NoGlobalDndNote extends StatelessWidget {
  const _NoGlobalDndNote();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.all(tokens.space.sm),
      decoration: BoxDecoration(
        color: tokens.colors.warningSoft.withValues(alpha: 0.5),
        border: Border.all(
          color: tokens.colors.warning.withValues(alpha: 0.45),
          width: tokens.stroke.hairline,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.warning,
            size: tokens.icons.medium,
            color: tokens.colors.warning,
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(
            child: Text(
              strings.text('settings.notification.sources.noGlobalDnd'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySources extends StatelessWidget {
  const _EmptySources();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.all(tokens.space.lg),
      decoration: BoxDecoration(
        color: tokens.surfaces.ground.fill,
        border: Border.all(
          color: tokens.surfaces.panel.border,
          width: tokens.stroke.hairline,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Column(
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.officialFleet,
            size: tokens.icons.large,
            color: tokens.colors.textDisabled,
          ),
          SizedBox(height: tokens.space.sm),
          Text(
            strings.text('settings.notification.sources.empty.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            strings.text('settings.notification.sources.empty.description'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

StarBridgeIconSemantic _sourceIcon(NotificationSourceKind kind) =>
    switch (kind) {
      NotificationSourceKind.officialFleet =>
        StarBridgeIconSemantic.officialFleet,
      NotificationSourceKind.community => StarBridgeIconSemantic.community,
      NotificationSourceKind.room => StarBridgeIconSemantic.room,
      NotificationSourceKind.operation => StarBridgeIconSemantic.operation,
      NotificationSourceKind.friends ||
      NotificationSourceKind.directMessages => StarBridgeIconSemantic.community,
    };

StarBridgeIconSemantic _sourceModeIcon(NotificationSourceMode mode) =>
    switch (mode) {
      NotificationSourceMode.normal => StarBridgeIconSemantic.connected,
      NotificationSourceMode.importantOnly => StarBridgeIconSemantic.warning,
      NotificationSourceMode.doNotDisturb => StarBridgeIconSemantic.reminder,
    };

String _sourceKindKey(NotificationSourceKind kind) => switch (kind) {
  NotificationSourceKind.officialFleet =>
    'settings.notification.sourceKind.officialFleet',
  NotificationSourceKind.community =>
    'settings.notification.sourceKind.community',
  NotificationSourceKind.room => 'settings.notification.sourceKind.room',
  NotificationSourceKind.operation =>
    'settings.notification.sourceKind.operation',
  NotificationSourceKind.friends => 'settings.notification.sourceKind.friends',
  NotificationSourceKind.directMessages =>
    'settings.notification.sourceKind.directMessages',
};

String _sourceModeKey(NotificationSourceMode mode) => switch (mode) {
  NotificationSourceMode.normal => 'settings.notification.mode.normal',
  NotificationSourceMode.importantOnly =>
    'settings.notification.mode.important',
  NotificationSourceMode.doNotDisturb =>
    'settings.notification.mode.doNotDisturb',
};

Color _sourceColor(BuildContext context, NotificationSourceKind kind) {
  final tokens = context.tokens;
  return switch (kind) {
    NotificationSourceKind.officialFleet =>
      tokens.domainColors.resolve(DomainColorRole.command).foreground,
    NotificationSourceKind.community =>
      tokens.domainColors.resolve(DomainColorRole.logistics).foreground,
    NotificationSourceKind.room => tokens.colors.success,
    NotificationSourceKind.friends ||
    NotificationSourceKind.directMessages => tokens.colors.success,
    NotificationSourceKind.operation =>
      tokens.domainColors.resolve(DomainColorRole.airCombat).foreground,
  };
}
