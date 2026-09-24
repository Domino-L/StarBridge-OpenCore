import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/preferences/app_preferences.dart';
import '../../app/preferences/app_preferences_port.dart';
import '../../app/preferences/app_preferences_projection.dart';
import '../../app/preferences/app_preferences_store.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../gameplay_time/gameplay_time_controller.dart';
import '../gameplay_time/gameplay_time_panel.dart';
import 'general_settings_appearance.dart';
import 'general_settings_behavior.dart';
import 'general_settings_language.dart';
import 'general_settings_sections.dart';

String _messageKey(AppPreferencesFailure? failure) => switch (failure) {
  AppPreferencesFailure.hostUnavailable =>
    'settings.general.error.hostUnavailable',
  AppPreferencesFailure.timeout => 'settings.general.error.timeout',
  AppPreferencesFailure.invalidResponse =>
    'settings.general.error.invalidResponse',
  AppPreferencesFailure.invalidValue => 'settings.general.error.invalidValue',
  AppPreferencesFailure.recoveredDefaults =>
    'settings.general.error.recoveredDefaults',
  AppPreferencesFailure.readFailed => 'settings.general.error.readFailed',
  AppPreferencesFailure.saveFailed => 'settings.general.error.saveFailed',
  AppPreferencesFailure.revisionConflict =>
    'settings.general.error.revisionConflict',
  AppPreferencesFailure.outcomeUncertain =>
    'settings.general.error.outcomeUncertain',
  AppPreferencesFailure.startupRegistrationFailed =>
    'settings.general.error.startupRegistrationFailed',
  null => 'settings.general.error.unavailable',
};

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({
    required this.preferences,
    this.gameplayTime,
    super.key,
  });

  final AppPreferencesPort preferences;
  final GameplayTimeController? gameplayTime;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPreferencesProjection>(
      valueListenable: preferences.projection,
      builder: (context, projection, _) {
        if (projection.isInitialLoading) {
          return const _SettingsLoading();
        }
        if (projection.phase == AppPreferencesPhase.unavailable &&
            projection.confirmed == null) {
          return _SettingsUnavailable(
            messageKey: _messageKey(projection.failure),
            onRetry: preferences.retry,
          );
        }
        return _GeneralSettingsContent(
          preferences: preferences,
          projection: projection,
          gameplayTime: gameplayTime,
        );
      },
    );
  }
}

class _GeneralSettingsContent extends StatelessWidget {
  const _GeneralSettingsContent({
    required this.preferences,
    required this.projection,
    this.gameplayTime,
  });

  final AppPreferencesPort preferences;
  final AppPreferencesProjection projection;
  final GameplayTimeController? gameplayTime;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final effective = projection.effective;
    final enabled = projection.canEdit;
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        tokens.space.xl,
        tokens.space.lg,
        tokens.space.xl,
        tokens.space.xxl,
      ),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.density.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.text('settings.general.title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                strings.text('settings.general.description'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
              if (projection.operation == AppPreferencesOperation.saving) ...[
                SizedBox(height: tokens.space.md),
                const LinearProgressIndicator(
                  key: Key('general-settings-saving'),
                ),
              ],
              if (projection.failure case final failure?) ...[
                SizedBox(height: tokens.space.md),
                _FailureBanner(
                  failure: failure,
                  messageKey: _messageKey(failure),
                  onRetry: projection.phase == AppPreferencesPhase.unavailable
                      ? preferences.retry
                      : null,
                ),
              ],
              SizedBox(height: tokens.space.lg),
              _SettingsPanel(
                icon: StarBridgeIconSemantic.generalData,
                title: strings.text('settings.general.language.title'),
                subtitle: strings.text('settings.general.language.description'),
                child: GeneralSettingsLanguageChoices(
                  value: effective.locale,
                  enabled: enabled,
                  onChanged: preferences.setLocale,
                ),
              ),
              SizedBox(height: tokens.space.md),
              _SettingsPanel(
                icon: StarBridgeIconSemantic.scene,
                title: strings.text('settings.general.appearance.title'),
                subtitle: strings.text(
                  'settings.general.appearance.description',
                ),
                child: Column(
                  children: [
                    GeneralSettingsAppearanceChoices(
                      value: effective.appearanceMode,
                      styleId: effective.designStyleId,
                      enabled: enabled,
                      onChanged: preferences.setAppearanceMode,
                    ),
                    Divider(height: tokens.space.lg),
                    _MotionSetting(
                      value:
                          effective.motionPreference == MotionPreference.reduce,
                      enabled: enabled,
                      onChanged: (value) => preferences.setMotionPreference(
                        value
                            ? MotionPreference.reduce
                            : MotionPreference.followSystem,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: tokens.space.md),
              _SettingsPanel(
                icon: StarBridgeIconSemantic.settings,
                title: strings.text('settings.general.behavior.title'),
                subtitle: strings.text('settings.general.behavior.description'),
                child: GeneralSettingsBehavior(
                  value: effective.applicationBehavior,
                  enabled: enabled,
                  onChanged: preferences.setApplicationBehavior,
                ),
              ),
              SizedBox(height: tokens.space.md),
              if (gameplayTime != null) ...[
                GameplayTimePanel(controller: gameplayTime!),
                SizedBox(height: tokens.space.md),
              ],
              const GeneralSettingsDataSections(),
              SizedBox(height: tokens.space.md),
              Text(
                strings.text('settings.general.deviceNotice'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final StarBridgeIconSemantic icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: tokens.space.xxs),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space.md),
          child,
        ],
      ),
    );
  }
}

class _MotionSetting extends StatelessWidget {
  const _MotionSetting({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final Future<bool> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('settings.general.motion.reduce'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tokens.space.xxs),
              Text(
                strings.text('settings.general.motion.reduceDescription'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.space.md),
        Switch(
          key: const Key('general-reduce-motion'),
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({
    required this.failure,
    required this.messageKey,
    this.onRetry,
  });

  final AppPreferencesFailure failure;
  final String messageKey;
  final Future<bool> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isWarning = switch (failure) {
      AppPreferencesFailure.recoveredDefaults ||
      AppPreferencesFailure.revisionConflict ||
      AppPreferencesFailure.outcomeUncertain => true,
      _ => false,
    };
    final semanticColor = isWarning
        ? tokens.colors.warning
        : tokens.colors.danger;
    return Container(
      padding: EdgeInsets.all(tokens.space.sm),
      decoration: BoxDecoration(
        color: isWarning ? tokens.colors.warningSoft : tokens.colors.dangerSoft,
        border: Border.all(color: semanticColor, width: tokens.stroke.regular),
        borderRadius: tokens.shape.small,
      ),
      child: Row(
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.warning,
            size: tokens.icons.medium,
            color: semanticColor,
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(child: Text(AppStrings.of(context).text(messageKey))),
          if (onRetry != null) ...[
            SizedBox(width: tokens.space.sm),
            OutlinedButton(
              key: const Key('general-settings-retry'),
              onPressed: () async {
                await onRetry!();
              },
              child: Text(
                AppStrings.of(context).text('settings.general.retry'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsLoading extends StatelessWidget {
  const _SettingsLoading();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            SizedBox(height: tokens.space.md),
            Text(AppStrings.of(context).text('settings.general.loading')),
          ],
        ),
      ),
    );
  }
}

class _SettingsUnavailable extends StatelessWidget {
  const _SettingsUnavailable({required this.messageKey, required this.onRetry});

  final String messageKey;
  final Future<bool> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.space.xl),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: StarBridgeSurface(
            role: SurfaceRole.raised,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StarBridgeIcon(
                  StarBridgeIconSemantic.warning,
                  size: tokens.icons.large,
                  color: tokens.colors.warning,
                ),
                SizedBox(height: tokens.space.md),
                Text(
                  strings.text('settings.general.unavailable.title'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: tokens.space.xs),
                Text(strings.text(messageKey)),
                SizedBox(height: tokens.space.md),
                OutlinedButton(
                  key: const Key('general-settings-retry'),
                  onPressed: () => onRetry(),
                  child: Text(strings.text('settings.general.retry')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
