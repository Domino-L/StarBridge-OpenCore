import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../game_log/game_log_controller.dart';
import 'overlay_settings_models.dart';
import 'overlay_settings_module.dart';
import 'overlay_settings_refresh_scope.dart';
import 'overlay_settings_sections.dart';
import 'overlay_workspace_page.dart';

class OverlaySettingsPage extends StatelessWidget {
  const OverlaySettingsPage({required this.module, this.gameLog, super.key});

  final OverlaySettingsModule module;
  final ValueListenable<GameLogView>? gameLog;

  @override
  Widget build(BuildContext context) =>
      OverlaySettingsRefreshScope(
        module: module,
        child: OverlaySettingsSections(menuPreview: module.menuPreview, child: _content(context)),
      );

  Widget _content(BuildContext context) {
    final workspace = module.workspace;
    if (workspace != null) {
      return OverlayWorkspacePage(module: workspace, scenes: module.scenes);
    }
    return ValueListenableBuilder<OverlaySettingsProjection>(
      valueListenable: module.projection,
      builder: (context, projection, _) => switch (projection.availability) {
        OverlaySettingsAvailability.loading => const _OverlayLoading(),
        OverlaySettingsAvailability.unavailable => _OverlayUnavailable(
          failure: projection.failure,
          onRetry: module.refresh,
        ),
        OverlaySettingsAvailability.available => _OverlayContent(
          module: module,
          projection: projection,
          gameLog: gameLog,
        ),
      },
    );
  }
}

class _OverlayContent extends StatelessWidget {
  const _OverlayContent({
    required this.module,
    required this.projection,
    required this.gameLog,
  });

  final OverlaySettingsModule module;
  final OverlaySettingsProjection projection;
  final ValueListenable<GameLogView>? gameLog;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final settings = projection.settings!;
    return SingleChildScrollView(
      key: const Key('overlay-settings-content'),
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
              _Header(windowAvailable: projection.windowAvailable),
              if (projection.operation == OverlaySettingsOperation.saving) ...[
                SizedBox(height: tokens.space.md),
                const LinearProgressIndicator(
                  key: Key('overlay-settings-saving'),
                ),
              ],
              if (projection.failure case final failure?) ...[
                SizedBox(height: tokens.space.md),
                _FailureBanner(failure: failure, onRetry: module.refresh),
              ],
              if (!projection.windowAvailable) ...[
                SizedBox(height: tokens.space.md),
                _WindowNotice(),
              ],
              SizedBox(height: tokens.space.lg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final controls = _Controls(
                    settings: settings,
                    enabled: projection.canEdit,
                    onSave: module.save,
                  );
                  final preview = _Preview(
                    settings: settings,
                    gameLog: gameLog,
                  );
                  if (constraints.maxWidth < 940) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        controls,
                        SizedBox(height: tokens.space.md),
                        preview,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 360, child: controls),
                      SizedBox(width: tokens.space.md),
                      Expanded(child: preview),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.windowAvailable});

  final bool windowAvailable;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final statusColor = windowAvailable
        ? tokens.colors.success
        : tokens.colors.warning;
    return LayoutBuilder(
      builder: (context, constraints) {
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.text('overlay.title'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.space.xs),
            Text(
              strings.text('overlay.description'),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ],
        );
        final badge = Container(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.sm,
            vertical: tokens.space.xs,
          ),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.42),
              width: tokens.stroke.hairline,
            ),
            borderRadius: tokens.shape.small,
          ),
          child: Text(
            strings.text(
              windowAvailable
                  ? 'overlay.status.ready'
                  : 'overlay.status.windowUnavailable',
            ),
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: statusColor),
          ),
        );
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              copy,
              SizedBox(height: tokens.space.sm),
              Align(alignment: AlignmentDirectional.centerStart, child: badge),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: copy),
            SizedBox(width: tokens.space.md),
            badge,
          ],
        );
      },
    );
  }
}

class _WindowNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      key: const Key('overlay-window-unavailable'),
      padding: EdgeInsets.all(tokens.space.md),
      decoration: BoxDecoration(
        color: tokens.colors.warningSoft,
        border: BorderDirectional(
          start: BorderSide(color: tokens.colors.warning, width: 2),
        ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('overlay.status.windowUnavailable'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SizedBox(height: tokens.space.xxs),
                Text(
                  strings.text('overlay.status.windowUnavailableBody'),
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

class _Controls extends StatelessWidget {
  const _Controls({
    required this.settings,
    required this.enabled,
    required this.onSave,
  });

  final OverlaySettingsValue settings;
  final bool enabled;
  final Future<bool> Function(OverlaySettingsValue value) onSave;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return StarBridgeSurface(
      key: const Key('overlay-controls'),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeading(
            icon: StarBridgeIconSemantic.settings,
            title: strings.text('overlay.settings.title'),
            description: strings.text('overlay.settings.description'),
          ),
          SizedBox(height: tokens.space.lg),
          _SwitchRow(
            key: const Key('overlay-enabled'),
            title: strings.text('overlay.enabled'),
            description: strings.text('overlay.enabled.description'),
            value: settings.enabled,
            enabled: enabled,
            onChanged: (value) => onSave(settings.copyWith(enabled: value)),
          ),
          Divider(height: tokens.space.xl),
          Text(
            strings.text('overlay.opacity'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SizedBox(height: tokens.space.xs),
          _OpacityEditor(
            value: settings.opacity,
            enabled: enabled,
            onChanged: (value) => onSave(settings.copyWith(opacity: value)),
          ),
          Divider(height: tokens.space.xl),
          Text(
            strings.text('overlay.position'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SizedBox(height: tokens.space.sm),
          Wrap(
            spacing: tokens.space.xs,
            runSpacing: tokens.space.xs,
            children: [
              for (final position in OverlaySettingsPosition.values)
                ChoiceChip(
                  key: Key('overlay-position-${position.name}'),
                  label: Text(
                    strings.text('overlay.position.${position.name}'),
                  ),
                  selected: settings.position == position,
                  onSelected: enabled
                      ? (_) => onSave(settings.copyWith(position: position))
                      : null,
                ),
            ],
          ),
          Divider(height: tokens.space.xl),
          _SwitchRow(
            key: const Key('overlay-show-team'),
            title: strings.text('overlay.showTeam'),
            description: strings.text('overlay.showTeam.description'),
            value: settings.showTeam,
            enabled: enabled,
            onChanged: (value) => onSave(settings.copyWith(showTeam: value)),
          ),
        ],
      ),
    );
  }
}

class _OpacityEditor extends StatefulWidget {
  const _OpacityEditor({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final Future<bool> Function(double value) onChanged;

  @override
  State<_OpacityEditor> createState() => _OpacityEditorState();
}

class _OpacityEditorState extends State<_OpacityEditor> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(covariant _OpacityEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            key: const Key('overlay-opacity'),
            value: _value,
            min: 0.35,
            max: 1,
            divisions: 13,
            label: '${(_value * 100).round()}%',
            onChanged: widget.enabled
                ? (value) => setState(() => _value = value)
                : null,
            onChangeEnd: widget.enabled ? widget.onChanged : null,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 46,
          child: Text('${(_value * 100).round()}%', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.description,
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String description;
  final bool value;
  final bool enabled;
  final Future<bool> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: tokens.space.xxs),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        SizedBox(width: tokens.space.sm),
        Switch(value: value, onChanged: enabled ? onChanged : null),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.settings, required this.gameLog});

  final OverlaySettingsValue settings;
  final ValueListenable<GameLogView>? gameLog;

  @override
  Widget build(BuildContext context) {
    final controller = gameLog;
    if (controller == null) {
      return _PreviewBody(
        settings: settings,
        game: const GameLogView(visible: true, error: 'unsupported'),
      );
    }
    return ValueListenableBuilder<GameLogView>(
      valueListenable: controller,
      builder: (context, value, _) =>
          _PreviewBody(settings: settings, game: value),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.settings, required this.game});

  final OverlaySettingsValue settings;
  final GameLogView game;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final alignment = switch (settings.position) {
      OverlaySettingsPosition.topLeft => AlignmentDirectional.topStart,
      OverlaySettingsPosition.topRight => AlignmentDirectional.topEnd,
      OverlaySettingsPosition.bottomLeft => AlignmentDirectional.bottomStart,
      OverlaySettingsPosition.bottomRight => AlignmentDirectional.bottomEnd,
    };
    return StarBridgeSurface(
      key: const Key('overlay-preview'),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeading(
            icon: StarBridgeIconSemantic.overlay,
            title: strings.text('overlay.preview.title'),
            description: strings.text('overlay.preview.description'),
          ),
          if (!settings.enabled) ...[
            SizedBox(height: tokens.space.sm),
            Text(
              strings.text('overlay.preview.disabled'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.colors.warning),
            ),
          ],
          SizedBox(height: tokens.space.md),
          Container(
            height: 390,
            padding: EdgeInsets.all(tokens.space.md),
            decoration: BoxDecoration(
              color: tokens.surfaces.ground.fill,
              border: Border.all(
                color: tokens.surfaces.status.border,
                width: tokens.stroke.hairline,
              ),
              borderRadius: tokens.shape.small,
            ),
            child: AnimatedAlign(
              duration: tokens.motion.pointerPageSwap,
              curve: tokens.motion.enterCurve,
              alignment: alignment,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Opacity(
                  opacity: settings.opacity,
                  child: _TelemetryCard(
                    game: game,
                    showTeam: settings.showTeam,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({required this.game, required this.showTeam});

  final GameLogView game;
  final bool showTeam;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final locale = Localizations.localeOf(context);
    final active = game.state == 'identified' && game.match == 'match';
    final region = game.serverRegion == null
        ? strings.text('gameLog.serverUnknown')
        : strings.text('gameLog.region${game.serverRegion}');
    final shard = game.serverShard ?? strings.text('gameLog.serverAreaUnknown');
    final location =
        game.locationDisplayName(locale.languageCode, locale.countryCode) ??
        strings.text('gameLog.locationUnknown');
    final ship =
        game.shipDisplayName(locale.languageCode, locale.countryCode) ??
        strings.text('gameLog.shipUnknown');
    final statusColor = active ? tokens.colors.success : tokens.colors.info;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaces.floating.fill,
        border: Border.all(
          color: statusColor.withValues(alpha: 0.62),
          width: tokens.stroke.regular,
        ),
        borderRadius: tokens.shape.small,
        boxShadow: tokens.surfaces.floating.shadows,
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StarBridgeIcon(
                  StarBridgeIconSemantic.statusGame,
                  size: tokens.icons.medium,
                  color: statusColor,
                ),
                SizedBox(width: tokens.space.sm),
                Expanded(
                  child: Text(
                    active
                        ? strings.text('overlay.preview.playing')
                        : strings.text('overlay.preview.waiting'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  game.channel,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: tokens.colors.accent),
                ),
              ],
            ),
            Divider(height: tokens.space.lg),
            _TelemetryFact(
              label: strings.text('gameLog.server'),
              value: region,
            ),
            _TelemetryFact(
              key: const Key('overlay-preview-shard'),
              label: strings.text('gameLog.serverArea'),
              value: shard,
            ),
            _TelemetryFact(
              label: strings.text('gameLog.location'),
              value: location,
            ),
            _TelemetryFact(label: strings.text('gameLog.ship'), value: ship),
            if (showTeam) ...[
              Divider(height: tokens.space.lg),
              Text(
                strings.text('overlay.preview.noTeam'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TelemetryFact extends StatelessWidget {
  const _TelemetryFact({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(
            child: Text(
              value,
              softWrap: true,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({
    required this.icon,
    required this.title,
    required this.description,
  });

  final StarBridgeIconSemantic icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StarBridgeIcon(
          icon,
          size: tokens.icons.medium,
          color: tokens.colors.accent,
        ),
        SizedBox(width: tokens.space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: tokens.space.xxs),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.failure, required this.onRetry});

  final OverlaySettingsFailure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final keyName = switch (failure) {
      OverlaySettingsFailure.hostUnavailable => 'hostUnavailable',
      OverlaySettingsFailure.readFailed => 'readFailed',
      OverlaySettingsFailure.writeFailed => 'writeFailed',
      OverlaySettingsFailure.writeConflict => 'writeConflict',
      OverlaySettingsFailure.invalidValue => 'invalidValue',
      OverlaySettingsFailure.invalidResponse => 'invalidResponse',
    };
    return Container(
      padding: EdgeInsets.all(tokens.space.md),
      decoration: BoxDecoration(
        color: tokens.colors.dangerSoft,
        border: Border.all(color: tokens.colors.danger),
        borderRadius: tokens.shape.small,
      ),
      child: Row(
        children: [
          Expanded(child: Text(strings.text('overlay.error.$keyName'))),
          SizedBox(width: tokens.space.sm),
          TextButton(
            onPressed: onRetry,
            child: Text(strings.text('overlay.retry')),
          ),
        ],
      ),
    );
  }
}

class _OverlayLoading extends StatelessWidget {
  const _OverlayLoading();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            SizedBox(height: tokens.space.md),
            Text(strings.text('overlay.loading')),
          ],
        ),
      ),
    );
  }
}

class _OverlayUnavailable extends StatelessWidget {
  const _OverlayUnavailable({required this.failure, required this.onRetry});

  final OverlaySettingsFailure? failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: StarBridgeSurface(
          key: const Key('overlay-settings-unavailable'),
          role: SurfaceRole.panel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarBridgeIcon(
                StarBridgeIconSemantic.warning,
                size: tokens.icons.large,
                color: tokens.colors.warning,
              ),
              SizedBox(height: tokens.space.md),
              Text(
                strings.text('overlay.unavailable.title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.space.xs),
              Text(strings.text('overlay.unavailable.body')),
              SizedBox(height: tokens.space.md),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                label: Text(strings.text('overlay.retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
