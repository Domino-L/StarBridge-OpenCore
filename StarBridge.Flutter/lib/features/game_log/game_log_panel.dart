import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../platform/window/gameplay_log_picker.dart';
import 'game_log_controller.dart';

class GameLogPanel extends StatelessWidget {
  const GameLogPanel({
    required this.controller,
    this.pickLog = pickGameplayLog,
    super.key,
  });
  final GameLogController controller;
  final Future<String?> Function() pickLog;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GameLogView>(
    valueListenable: controller,
    builder: (context, value, _) {
      if (!value.visible) return const SizedBox.shrink();
      final t = context.tokens;
      String text(String key) => AppStrings.of(context).text('gameLog.$key');
      final status =
          value.error ?? (value.match != 'unknown' ? value.match : value.state);
      final warning =
          value.error != null ||
          const {
            'mismatch',
            'ambiguous',
            'unreadable',
            'differentInstallation',
            'unknown',
            'notFound',
            'multipleLogs',
            'otherVersion',
          }.contains(status);
      final color = warning
          ? t.colors.warning
          : status == 'match'
          ? t.colors.success
          : t.colors.textSecondary;
      final enabled = !value.busy && value.error != 'unsupported';
      return StarBridgeSurface(
        role: SurfaceRole.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StarBridgeIcon(
                  StarBridgeIconSemantic.account,
                  size: t.icons.medium,
                  color: t.colors.accent,
                ),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: Text(
                    text('title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space.sm),
            Text(
              text('description'),
              style: TextStyle(color: t.colors.textSecondary),
            ),
            SizedBox(height: t.space.md),
            Text(text('version')),
            SizedBox(height: t.space.sm),
            Wrap(
              spacing: t.space.sm,
              runSpacing: t.space.sm,
              children: [
                for (final channel in value.channels)
                  InputChip(
                    label: Text(
                      const {'LIVE', 'PTU'}.contains(channel)
                          ? text(channel)
                          : channel,
                    ),
                    selected: value.channel == channel,
                    onSelected: enabled
                        ? (selected) {
                            if (selected && value.channel != channel) {
                              controller.run(
                                command: 'configure',
                                channel: channel,
                              );
                            }
                          }
                        : null,
                    onDeleted: enabled && channel != 'LIVE'
                        ? () =>
                              _removeVersion(context, controller, channel, text)
                        : null,
                    deleteIcon: channel == 'LIVE'
                        ? null
                        : StarBridgeIcon(
                            StarBridgeIconSemantic.remove,
                            size: t.icons.small,
                          ),
                    deleteButtonTooltipMessage: text('removeVersion'),
                  ),
                ActionChip(
                  avatar: StarBridgeIcon(
                    StarBridgeIconSemantic.add,
                    size: t.icons.small,
                  ),
                  label: Text(text('addVersion')),
                  onPressed: enabled
                      ? () => controller.addVersion(pickLog)
                      : null,
                ),
              ],
            ),
            SizedBox(height: t.space.sm),
            Text(
              text(
                value.verifiedChannels.contains(value.channel)
                    ? 'versionReady'
                    : 'versionPending',
              ),
              style: TextStyle(color: t.colors.textSecondary),
            ),
            SizedBox(height: t.space.md),
            Text(
              text(value.selection),
              style: TextStyle(color: t.colors.textSecondary),
            ),
            SizedBox(height: t.space.sm),
            if (value.path != null) ...[
              SelectableText(
                value.path!,
                style: TextStyle(color: t.colors.textSecondary),
              ),
              SizedBox(height: t.space.md),
            ],
            Wrap(
              spacing: t.space.xl,
              runSpacing: t.space.sm,
              children: [
                Text('${text('expected')} · ${value.expectedHandle ?? '—'}'),
                Text('${text('detected')} · ${value.handle ?? '—'}'),
              ],
            ),
            SizedBox(height: t.space.md),
            Row(
              children: [
                if (value.busy) ...[
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: t.space.sm),
                ],
                Expanded(
                  child: Text(
                    text(value.busy ? 'busy' : status),
                    style: TextStyle(color: color),
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space.md),
            Wrap(
              spacing: t.space.sm,
              key: const Key('game-log-actions'),
              runSpacing: t.space.sm,
              children: [
                FilledButton(
                  onPressed: enabled
                      ? () => controller.run(command: 'find')
                      : null,
                  child: Text(text('find')),
                ),
                OutlinedButton(
                  onPressed: enabled ? () => controller.pick(pickLog) : null,
                  child: Text(text('select')),
                ),
                if (value.enabled)
                  OutlinedButton(
                    onPressed: enabled
                        ? () => controller.run(command: 'stop')
                        : null,
                    child: Text(text('stop')),
                  )
                else
                  OutlinedButton(
                    onPressed: enabled
                        ? () => controller.run(command: 'resume')
                        : null,
                    child: Text(text('resume')),
                  ),
                TextButton(
                  onPressed: enabled
                      ? () => controller.run(command: 'retry')
                      : null,
                  child: Text(text('retry')),
                ),
              ],
            ),
            if (value.observedAt case final checkedAt?) ...[
              SizedBox(height: t.space.sm),
              Text(
                '${text('lastChecked')} · '
                '${MaterialLocalizations.of(context).formatShortDate(checkedAt)} '
                '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(checkedAt), alwaysUse24HourFormat: Localizations.localeOf(context).languageCode == 'zh')}',
                key: const Key('game-log-last-checked'),
                style: TextStyle(color: t.colors.textSecondary),
              ),
            ],
          ],
        ),
      );
    },
  );

  static Future<void> _removeVersion(
    BuildContext context,
    GameLogController controller,
    String channel,
    String Function(String key) text,
  ) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          text('removeVersionTitle').replaceAll('{version}', channel),
        ),
        content: Text(text('removeVersionDetail')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(text('keepVersion')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(text('removeVersion')),
          ),
        ],
      ),
    );
    if (remove == true && context.mounted) {
      await controller.run(command: 'removeVersion', channel: channel);
    }
  }
}
