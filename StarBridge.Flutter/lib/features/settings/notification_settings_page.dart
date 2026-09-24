import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'notification_settings_activity.dart';
import 'notification_settings_channels.dart';
import 'notification_settings_common.dart';
import 'notification_settings_models.dart';
import 'notification_settings_module.dart';
import 'notification_settings_play_reminders.dart';
import 'notification_settings_sources.dart';
import 'notification_audio_controller.dart';
import 'notification_audio_panel.dart';
import 'settings_capability_overview.dart';
import 'settings_models.dart';
import 'notification_editor_frame.dart';
import 'notification_connected_panels.dart';
import 'notification_settings_comparison.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/host/desktop_notification_port.dart';

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({
    required this.module,
    this.audio,
    this.desktop,
    this.session,
    super.key,
  });

  final NotificationSettingsModule module;
  final NotificationAudioController? audio;
  final DesktopNotificationPort? desktop;
  final BridgeClientSession? session;

  @override
  Widget build(BuildContext context) => NotificationEditorFrame(
    owner: module,
    session: session,
    child: _NotificationSettingsBody(
      module: module,
      audio: audio,
      desktop: desktop,
      session: session,
    ),
  );
}

class _NotificationSettingsBody extends StatelessWidget {
  const _NotificationSettingsBody({
    required this.module,
    this.audio,
    this.desktop,
    this.session,
  });
  final NotificationSettingsModule module;
  final NotificationAudioController? audio;
  final DesktopNotificationPort? desktop;
  final BridgeClientSession? session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NotificationSettingsProjection>(
      valueListenable: module.projection,
      builder: (context, projection, _) {
        final content = switch (projection.availability) {
          NotificationSettingsAvailability.loading =>
            const NotificationLoadingView(),
          NotificationSettingsAvailability.signedOut =>
            const NotificationStateView(
              key: Key('notification-settings-signed-out'),
              icon: StarBridgeIconSemantic.login,
              titleKey: 'settings.notification.signedOut.title',
              bodyKey: 'settings.notification.signedOut.body',
            ),
          NotificationSettingsAvailability.unavailable => NotificationStateView(
            key: const Key('notification-settings-unavailable'),
            icon: StarBridgeIconSemantic.warning,
            titleKey: 'settings.notification.unavailable.title',
            bodyKey: _failureKey(projection.failure),
            actionKey: 'settings.notification.retry',
            onAction: module.refresh,
            warning: true,
          ),
          NotificationSettingsAvailability.available =>
            _NotificationSettingsContent(
              module: module,
              projection: projection,
              audio: audio,
              desktop: desktop,
              session: session,
            ),
        };
        if ((audio == null && session == null) ||
            projection.availability ==
                NotificationSettingsAvailability.available) {
          return content;
        }
        return ListView(
          children: [
            if (audio != null)
              Padding(
                padding: EdgeInsets.all(context.tokens.space.lg),
                child: NotificationAudioPanel(controller: audio!),
              ),
            content,
            if (session != null)
              NotificationConnectedPanels(
                key: ValueKey((
                  'notification-connected',
                  NotificationDraftScope.of(context)?.epoch,
                )),
                session: session!,
              ),
          ],
        );
      },
    );
  }
}

String _failureKey(NotificationSettingsFailure? failure) => switch (failure) {
  NotificationSettingsFailure.hostUnavailable =>
    'settings.notification.error.hostUnavailable',
  NotificationSettingsFailure.readFailed =>
    'settings.notification.error.readFailed',
  NotificationSettingsFailure.writeFailed =>
    'settings.notification.error.writeFailed',
  NotificationSettingsFailure.writeConflict =>
    'settings.notification.error.writeConflict',
  NotificationSettingsFailure.invalidResponse =>
    'settings.notification.error.invalidResponse',
  null => 'settings.notification.error.unavailable',
};

class _NotificationSettingsContent extends StatelessWidget {
  const _NotificationSettingsContent({
    required this.module,
    required this.projection,
    this.audio,
    this.desktop,
    this.session,
  });

  final NotificationSettingsModule module;
  final NotificationSettingsProjection projection;
  final NotificationAudioController? audio;
  final DesktopNotificationPort? desktop;
  final BridgeClientSession? session;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final drafts = NotificationDraftScope.of(context);
    final saved = projection.settings!;
    final settings = drafts?.value('notifications', saved) ?? saved;
    final enabled = projection.canEdit && !(drafts?.saving ?? false);
    Future<bool> stage(NotificationSettingsValue next) async {
      if (drafts == null) return module.save(next);
      final revision = projection.revision;
      drafts.edit(
        'notifications',
        saved,
        sameNotificationSettings(saved, next) ? saved : next,
        (value) async {
          if (module.projection.value.revision != revision) return false;
          return module.save(value);
        },
      );
      return true;
    }

    return SingleChildScrollView(
      key: const Key('notification-settings-content'),
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
              if (settings.localInAppOnly) ...[
                Text(
                  strings.text('settings.notification.title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(strings.text('settings.notification.local.description')),
              ] else
                _PageHeader(strings: strings),
              if (projection.operation ==
                  NotificationSettingsOperation.saving) ...[
                SizedBox(height: tokens.space.md),
                const LinearProgressIndicator(
                  key: Key('notification-settings-saving'),
                ),
              ],
              if (projection.failure case final failure?) ...[
                SizedBox(height: tokens.space.md),
                NotificationFailureBanner(
                  messageKey: _failureKey(failure),
                  onRetry: module.refresh,
                ),
              ],
              SizedBox(height: tokens.space.lg),
              if (audio != null) ...[
                NotificationAudioPanel(controller: audio!),
                SizedBox(height: tokens.space.md),
              ],
              _ResponsivePair(
                primaryFlex: 3,
                secondaryFlex: 2,
                primary: NotificationChannelPanel(
                  key: ValueKey(('notification-channels', drafts?.epoch)),
                  desktop: desktop,
                  showSound: audio == null,
                  settings: settings,
                  enabled: enabled,
                  onSave: stage,
                ),
                secondary: NotificationPreviewPanel(
                  settings: settings,
                  enabled: enabled,
                  onSave: stage,
                ),
              ),
              SizedBox(height: tokens.space.md),
              if (!settings.localInAppOnly) ...[
                NotificationSourceRulesPanel(
                  settings: settings,
                  enabled: enabled,
                  onSave: stage,
                ),
                SizedBox(height: tokens.space.md),
                _ResponsivePair(
                  primaryFlex: 3,
                  secondaryFlex: 2,
                  primary: PlayerActivityNotificationPanel(
                    settings: settings,
                    enabled: enabled,
                    onSave: stage,
                  ),
                  secondary: ContinuousPlayReminderPanel(
                    key: ValueKey(('notification-play', drafts?.epoch)),
                    settings: settings,
                    enabled: enabled,
                    onSave: stage,
                  ),
                ),
              ] else if (session != null)
                NotificationConnectedPanels(
                  key: ValueKey(('notification-connected', drafts?.epoch)),
                  session: session!,
                )
              else
                const PlannedSettingsCapabilities(
                  section: SettingsSection.notifications,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.text('settings.notification.title'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.space.xs),
            Text(
              strings.text('settings.notification.description'),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ],
        );
        final scope = Wrap(
          spacing: tokens.space.xs,
          runSpacing: tokens.space.xs,
          children: [
            _ScopeBadge(
              icon: StarBridgeIconSemantic.diagnostics,
              label: strings.text('settings.notification.scope.device'),
              color: tokens.colors.info,
            ),
            _ScopeBadge(
              icon: StarBridgeIconSemantic.account,
              label: strings.text('settings.notification.scope.account'),
              color: tokens.colors.success,
            ),
          ],
        );
        if (constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              copy,
              SizedBox(height: tokens.space.sm),
              scope,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: copy),
            SizedBox(width: tokens.space.md),
            scope,
          ],
        );
      },
    );
  }
}

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final StarBridgeIconSemantic icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(
          color: color.withValues(alpha: 0.38),
          width: tokens.stroke.hairline,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StarBridgeIcon(icon, size: tokens.icons.small, color: color),
          SizedBox(width: tokens.space.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({
    required this.primaryFlex,
    required this.secondaryFlex,
    required this.primary,
    required this.secondary,
  });

  final int primaryFlex;
  final int secondaryFlex;
  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 980) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              SizedBox(height: tokens.space.md),
              secondary,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: primaryFlex, child: primary),
            SizedBox(width: tokens.space.md),
            Expanded(flex: secondaryFlex, child: secondary),
          ],
        );
      },
    );
  }
}
