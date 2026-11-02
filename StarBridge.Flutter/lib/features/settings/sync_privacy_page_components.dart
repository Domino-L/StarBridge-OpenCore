import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import 'help_support_action.dart';
import 'help_support_waiting.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'sync_privacy_models.dart';

class SyncPrivacyVisibilityMap extends StatelessWidget {
  const SyncPrivacyVisibilityMap({required this.settings, super.key});

  final SyncPrivacySettingsValue settings;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: const Key('privacy-visibility-map'),
      role: SurfaceRole.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text('settings.privacy.map.title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            strings.text('settings.privacy.map.description'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SizedBox(height: tokens.space.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 840
                  ? 3
                  : constraints.maxWidth >= 520
                  ? 2
                  : 1;
              final gap = tokens.space.sm;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _AudienceCard(
                    width: width,
                    icon: StarBridgeIconSemantic.friends,
                    titleKey: 'settings.privacy.map.friends',
                    body: strings
                        .text('settings.privacy.map.friendsBody')
                        .replaceAll(
                          '{count}',
                          settings.friendDefaults.enabledCount.toString(),
                        ),
                    statusKey: settings.realtimeSyncEnabled
                        ? 'settings.privacy.map.accountDefault'
                        : 'settings.privacy.map.paused',
                    color: tokens.colors.stateAccent,
                    softColor: tokens.colors.stateAccentSoft,
                  ),
                  _AudienceCard(
                    width: width,
                    icon: StarBridgeIconSemantic.operation,
                    titleKey: 'settings.privacy.map.collaboration',
                    body: strings.text(
                      'settings.privacy.map.collaborationBody',
                    ),
                    statusKey: 'settings.privacy.map.temporary',
                    color: tokens.colors.info,
                    softColor: tokens.colors.infoSoft,
                  ),
                  _AudienceCard(
                    width: width,
                    icon: StarBridgeIconSemantic.privacy,
                    titleKey: 'settings.privacy.map.others',
                    body: strings.text('settings.privacy.map.othersBody'),
                    statusKey: 'settings.privacy.map.noAutomaticAccess',
                    color: tokens.colors.textSecondary,
                    softColor: tokens.surfaces.panel.fill,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AudienceCard extends StatelessWidget {
  const _AudienceCard({
    required this.width,
    required this.icon,
    required this.titleKey,
    required this.body,
    required this.statusKey,
    required this.color,
    required this.softColor,
  });

  final double width;
  final StarBridgeIconSemantic icon;
  final String titleKey;
  final String body;
  final String statusKey;
  final Color color;
  final Color softColor;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 154),
      padding: EdgeInsets.all(tokens.space.md),
      decoration: BoxDecoration(
        color: tokens.surfaces.panel.fill,
        border: Border.all(
          color: tokens.surfaces.panel.border,
          width: tokens.stroke.regular,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(icon, size: tokens.icons.medium, color: color),
          SizedBox(height: tokens.space.sm),
          Text(
            strings.text(titleKey),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tokens.space.xxs),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
          SizedBox(height: tokens.space.sm),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.space.sm,
              vertical: tokens.space.xxs,
            ),
            decoration: BoxDecoration(
              color: softColor,
              borderRadius: tokens.shape.small,
            ),
            child: Text(
              strings.text(statusKey),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class SyncPrivacySettingsPanel extends StatelessWidget {
  const SyncPrivacySettingsPanel({
    required this.icon,
    required this.titleKey,
    required this.descriptionKey,
    required this.child,
    this.sourceKey,
    super.key,
  });

  final StarBridgeIconSemantic icon;
  final String titleKey;
  final String descriptionKey;
  final String? sourceKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarBridgeIcon(
                icon,
                size: tokens.icons.medium,
                color: tokens.colors.textSecondary,
              ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text(titleKey),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      strings.text(descriptionKey),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (sourceKey != null) ...[
                SizedBox(width: tokens.space.sm),
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
                    strings.text(sourceKey!),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: tokens.space.md),
          child,
        ],
      ),
    );
  }
}

class SyncPrivacySettingRow extends StatelessWidget {
  const SyncPrivacySettingRow({
    required this.settingKey,
    required this.titleKey,
    required this.descriptionKey,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.showDivider = true,
    super.key,
  });

  final Key settingKey;
  final String titleKey;
  final String descriptionKey;
  final bool value;
  final bool enabled;
  final Future<bool> Function(bool value) onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: tokens.surfaces.panel.border,
                  width: tokens.stroke.hairline,
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text(titleKey),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                SizedBox(height: tokens.space.xxs),
                Text(
                  strings.text(descriptionKey),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? tokens.colors.textSecondary
                        : tokens.colors.textDisabled,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.space.md),
          StarBridgeSwitch(
            controlKey: settingKey,
            label: strings.text(titleKey),
            value: value,
            onChanged: enabled
                ? (next) => runStarBridgeActivation<void>(
                    currentStarBridgeActivationSource,
                    () async {
                      await onChanged(next);
                    },
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class SyncPrivacyEventChoices extends StatelessWidget {
  const SyncPrivacyEventChoices({
    required this.settings,
    required this.enabled,
    required this.onSave,
    super.key,
  });

  final SyncPrivacySettingsValue settings;
  final bool enabled;
  final Future<bool> Function(SyncPrivacySettingsValue) onSave;

  @override
  Widget build(BuildContext context) {
    final events = settings.eventSharing;
    return Column(
      children: [
        SyncPrivacySettingRow(
          settingKey: const Key('privacy-events-presence'),
          titleKey: 'settings.privacy.events.presence',
          descriptionKey: 'settings.privacy.events.presenceDescription',
          value: events.presence,
          enabled: enabled,
          onChanged: (value) => onSave(
            settings.copyWith(eventSharing: events.copyWith(presence: value)),
          ),
        ),
        SyncPrivacySettingRow(
          settingKey: const Key('privacy-events-server'),
          titleKey: 'settings.privacy.events.server',
          descriptionKey: 'settings.privacy.events.serverDescription',
          value: events.server,
          enabled: enabled,
          onChanged: (value) => onSave(
            settings.copyWith(eventSharing: events.copyWith(server: value)),
          ),
        ),
        SyncPrivacySettingRow(
          settingKey: const Key('privacy-events-ship'),
          titleKey: 'settings.privacy.events.ship',
          descriptionKey: 'settings.privacy.events.shipDescription',
          value: events.ship,
          enabled: enabled,
          onChanged: (value) => onSave(
            settings.copyWith(eventSharing: events.copyWith(ship: value)),
          ),
        ),
        SyncPrivacySettingRow(
          settingKey: const Key('privacy-events-location'),
          titleKey: 'settings.privacy.events.location',
          descriptionKey: 'settings.privacy.events.locationDescription',
          value: events.location,
          enabled: enabled,
          onChanged: (value) => onSave(
            settings.copyWith(eventSharing: events.copyWith(location: value)),
          ),
        ),
        SyncPrivacySettingRow(
          settingKey: const Key('privacy-events-life'),
          titleKey: 'settings.privacy.events.life',
          descriptionKey: 'settings.privacy.events.lifeDescription',
          value: events.life,
          enabled: enabled,
          onChanged: (value) => onSave(
            settings.copyWith(eventSharing: events.copyWith(life: value)),
          ),
          showDivider: false,
        ),
      ],
    );
  }
}

class SyncPrivacyBoundaryNote extends StatelessWidget {
  const SyncPrivacyBoundaryNote({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    super.key,
  });

  final StarBridgeIconSemantic icon;
  final String titleKey;
  final String bodyKey;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarBridgeIcon(
            icon,
            size: tokens.icons.medium,
            color: tokens.colors.textSecondary,
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text(titleKey),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                SizedBox(height: tokens.space.xxs),
                Text(
                  strings.text(bodyKey),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SyncPrivacyFailureBanner extends StatelessWidget {
  const SyncPrivacyFailureBanner({
    required this.messageKey,
    required this.onRetry,
    super.key,
  });

  final String messageKey;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.all(tokens.space.sm),
      decoration: BoxDecoration(
        color: tokens.colors.warningSoft,
        border: Border.all(
          color: tokens.colors.warning,
          width: tokens.stroke.regular,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Row(
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.warning,
            size: tokens.icons.medium,
            color: tokens.colors.warning,
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(child: Text(strings.text(messageKey))),
          SizedBox(width: tokens.space.sm),
          HelpSupportAction(
            controlKey: const Key('sync-privacy-retry'),
            kind: StarBridgeActionKind.secondary,
            onActivate: (source) =>
                runStarBridgeActivation<void>(source, () async {
                  await onRetry();
                }),
            child: Text(strings.text('settings.privacy.retry')),
          ),
        ],
      ),
    );
  }
}

/// Decoration of the owner's pending operation; never starts or finishes it.
/// Keep the existing scroll body mounted and bounded, with feedback outside it.
class SyncPrivacyOperationFrame extends StatelessWidget {
  const SyncPrivacyOperationFrame({
    required this.operation,
    required this.source,
    required this.phase,
    required this.child,
    this.failureFeedback,
    super.key,
  });
  final SyncPrivacyOperation operation;
  final InteractionSource source;
  final int phase;
  final Widget child;
  final Widget? failureFeedback;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tokens = context.tokens;
      final feedback = operation == SyncPrivacyOperation.none
          ? const SizedBox.shrink()
          : Padding(
              padding: EdgeInsets.all(tokens.space.md),
              child: HelpSupportWaiting(
                key: ValueKey(('sync-privacy-operation', phase)),
                source: source,
                label: AppStrings.of(context).text(
                  operation == SyncPrivacyOperation.saving
                      ? 'privacy.local.saving'
                      : 'settings.privacy.loading',
                ),
              ),
            );
      return Column(
        mainAxisSize: constraints.hasBoundedHeight
            ? MainAxisSize.max
            : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          feedback,
          if (failureFeedback case final failure?)
            Padding(padding: EdgeInsets.all(tokens.space.md), child: failure),
          if (constraints.hasBoundedHeight) Expanded(child: child) else child,
        ],
      );
    },
  );
}

class SyncPrivacyLoadingView extends StatelessWidget {
  const SyncPrivacyLoadingView({
    this.source = InteractionSource.programmatic,
    this.phase = 0,
    super.key,
  });
  final InteractionSource source;
  final int phase;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.space.xl),
        child: HelpSupportWaiting(
          key: ValueKey(('sync-privacy-loading', phase)),
          source: source,
          label: AppStrings.of(context).text('settings.privacy.loading'),
        ),
      ),
    );
  }
}

class SyncPrivacyStateView extends StatelessWidget {
  const SyncPrivacyStateView({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    this.actionKey,
    this.onAction,
    this.warning = false,
    super.key,
  });

  final StarBridgeIconSemantic icon;
  final String titleKey;
  final String bodyKey;
  final String? actionKey;
  final Future<void> Function()? onAction;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.space.xl),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: StarBridgeSurface(
            role: SurfaceRole.raised,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StarBridgeIcon(
                  icon,
                  size: tokens.icons.large,
                  color: warning ? tokens.colors.warning : tokens.colors.accent,
                ),
                SizedBox(height: tokens.space.md),
                Text(
                  strings.text(titleKey),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: tokens.space.xs),
                Text(
                  strings.text(bodyKey),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
                if (actionKey != null && onAction != null) ...[
                  SizedBox(height: tokens.space.lg),
                  HelpSupportAction(
                    controlKey: const Key('sync-privacy-state-action'),
                    kind: StarBridgeActionKind.secondary,
                    onActivate: (source) =>
                        runStarBridgeActivation<void>(source, () async {
                          await onAction!();
                        }),
                    icon: StarBridgeIconSemantic.refresh,
                    child: Text(strings.text(actionKey!)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmRealtimePause(
  BuildContext context, {
  required bool hasActiveCollaboration,
}) async {
  final strings = AppStrings.of(context);
  return await showStarBridgeDialog<bool>(
        context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.text('settings.privacy.pauseDialog.title')),
          content: Text(
            strings.text(
              hasActiveCollaboration
                  ? 'settings.privacy.pauseDialog.activeBody'
                  : 'settings.privacy.pauseDialog.body',
            ),
          ),
          actions: [
            HelpSupportAction(
              controlKey: const Key('sync-privacy-pause-cancel'),
              onActivate: (source) => dismissStarBridgeDialog<bool>(
                dialogContext,
                source: source,
                result: false,
              ),
              child: Text(strings.text('settings.privacy.pauseDialog.cancel')),
            ),
            HelpSupportAction(
              controlKey: const Key('sync-privacy-pause-confirm'),
              kind: StarBridgeActionKind.primary,
              onActivate: (source) => dismissStarBridgeDialog<bool>(
                dialogContext,
                source: source,
                result: true,
              ),
              child: Text(strings.text('settings.privacy.pauseDialog.confirm')),
            ),
          ],
        ),
      ) ??
      false;
}
