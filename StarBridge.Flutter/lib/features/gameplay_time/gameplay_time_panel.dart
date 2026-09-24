import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../platform/window/gameplay_log_picker.dart';
import 'gameplay_time_controller.dart';

String gameplayDuration(AppStrings strings, int seconds) => strings
    .text('gameplay.duration')
    .replaceAll('{hours}', '${seconds ~/ 3600}')
    .replaceAll('{minutes}', '${seconds ~/ 60 % 60}');

class GameplayTimePanel extends StatefulWidget {
  const GameplayTimePanel({
    required this.controller,
    this.pickLog = pickGameplayLog,
    super.key,
  });
  final GameplayTimeController controller;
  final Future<String?> Function() pickLog;

  @override
  State<GameplayTimePanel> createState() => _GameplayTimePanelState();
}

class _GameplayTimePanelState extends State<GameplayTimePanel> {
  bool _dialogOpen = false;

  Future<void> _reset() async {
    if (_dialogOpen) return;
    final controller = widget.controller;
    await controller.resetTime(() async {
      if (!mounted || controller != widget.controller || _dialogOpen) {
        return false;
      }
      _dialogOpen = true;
      try {
        return await showDialog<bool>(
              context: context,
              builder: (dialogContext) =>
                  ValueListenableBuilder<GameplayTimeView>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      if (!value.visible ||
                          value.operation != 'resetConfirmation') {
                        final route = ModalRoute.of(dialogContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          // The dialog can still rebuild during its exit animation.
                          // Only remove this route, never pop the page beneath it.
                          if (dialogContext.mounted &&
                              route != null && route.isActive) {
                            Navigator.of(dialogContext).removeRoute(route, false);
                          }
                        });
                        return const SizedBox.shrink();
                      }
                      String text(String key) =>
                          AppStrings.of(context).text('gameplay.reset.$key');
                      return AlertDialog(
                        key: const Key('gameplay-reset-confirmation'),
                        title: Text(text('title')),
                        content: Text(text('body')),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: Text(text('keep')),
                          ),
                          TextButton(
                            key: const Key('gameplay-reset-confirm'),
                            style: TextButton.styleFrom(
                              foregroundColor: context.tokens.colors.danger,
                            ),
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: Text(text('action')),
                          ),
                        ],
                      );
                    },
                  ),
            ) ??
            false;
      } finally {
        _dialogOpen = false;
      }
    });
  }

  Future<void> _import() async {
    final controller = widget.controller;
    await controller.importHistory(widget.pickLog);
    if (!mounted || controller != widget.controller || _dialogOpen) return;
    final preview = controller.value.preview;
    if (preview == null) return;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _HistoryDialog(controller: controller, preview: preview),
      );
    } finally {
      _dialogOpen = false;
      controller.cancelPreview(preview);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<GameplayTimeView>(
    valueListenable: widget.controller,
    builder: (context, state, _) {
      if (!state.visible) return const SizedBox.shrink();
      final tokens = context.tokens;
      final strings = AppStrings.of(context);
      String text(String key) => strings.text('gameplay.$key');
      final error = state.error;
      final status = state.busy
          ? state.operation ?? 'stats'
          : error == 'unsupported'
          ? 'unsupported'
          : error == 'visibilityUnconfirmed'
          ? 'visibilityError'
          : error == 'stopUnconfirmed' ||
                error != null && state.consent == 'declined'
          ? 'stopError'
          : error == 'unavailable'
          ? 'readError'
          : error != null
          ? 'error'
          : state.consent != 'allowed'
          ? 'stopped'
          : state.recording
          ? 'recording'
          : state.gameState == 'unknown'
          ? 'gameUnknown'
          : 'waiting';
      final enabled =
          !state.busy && state.preview == null && error != 'unsupported';
      return StarBridgeSurface(
        key: const Key('gameplay-time-panel'),
        role: SurfaceRole.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StarBridgeIcon(
                  StarBridgeIconSemantic.playtime,
                  size: tokens.icons.medium,
                  color: tokens.colors.textSecondary,
                ),
                SizedBox(width: tokens.space.sm),
                Expanded(
                  child: Text(
                    text('title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.space.sm),
            Text(
              text('description'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('gameplay-time-explanation'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    scrollable: true,
                    title: Text(text('explanationTitle')),
                    content: Text(text('explanationBody')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          MaterialLocalizations.of(dialogContext)
                              .closeButtonLabel,
                        ),
                      ),
                    ],
                  ),
                ),
                child: Text(text('explanationTitle')),
              ),
            ),
            SizedBox(height: tokens.space.sm),
            _GameplaySwitch(
              label: text('recordSwitch'),
              value: state.consent == 'allowed',
              controlKey: const Key('gameplay-time-record-switch'),
              onChanged: enabled ? widget.controller.setAllowed : null,
            ),
            if (state.historySupported)
              _GameplaySwitch(
                label: text('profileSwitch'),
                value: state.showOnProfile,
                controlKey: const Key('gameplay-time-profile-switch'),
                onChanged: enabled ? widget.controller.setVisibility : null,
              ),
            if (state.busy && state.operation != 'resetConfirmation') ...[
              SizedBox(height: tokens.space.sm),
              const LinearProgressIndicator(key: Key('gameplay-time-busy')),
              SizedBox(height: tokens.space.sm),
            ],
            Text(
              text(status),
              key: const Key('gameplay-time-status'),
              style: TextStyle(
                color: error != null
                    ? tokens.colors.warning
                    : tokens.colors.textSecondary,
              ),
            ),
            if (state.seconds != null) ...[
              SizedBox(height: tokens.space.sm),
              Text(
                '${text('localTotal')}: ${gameplayDuration(strings, state.seconds!)}',
                key: const Key('gameplay-time-total'),
              ),
            ],
            if (state.seconds != null &&
                state.savedSeconds != null &&
                state.seconds! > state.savedSeconds! &&
                error != null)
              Text(
                text('unsaved'),
                style: TextStyle(color: tokens.colors.warning),
              ),
            if (error != null && error != 'unsupported')
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('gameplay-time-retry'),
                  onPressed: enabled ? widget.controller.retry : null,
                  child: Text(text('retry')),
                ),
              ),
            if (widget.controller.resetSupported) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('gameplay-reset-open'),
                  onPressed: enabled && state.resetState != 'pending'
                      ? _reset
                      : null,
                  child: Text(text('reset.action')),
                ),
              ),
              if (state.resetState != null && state.resetState != 'idle')
                Text(
                  text('reset.${state.resetState}'),
                  key: const Key('gameplay-reset-status'),
                ),
            ],
            if (state.historySupported) ...[
              Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.space.md),
                child: const Divider(height: 1),
              ),
              Text(
                text('historyTitle'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                text('history.${state.historyError ?? state.historyState}'),
                key: const Key('gameplay-history-status'),
              ),
              if (state.historicalSeconds > 0) ...[
                SizedBox(height: tokens.space.xs),
                Text(
                  '${text('importedTotal')}: ${gameplayDuration(strings, state.historicalSeconds)}',
                ),
              ],
              if (state.historyState != 'imported') ...[
                SizedBox(height: tokens.space.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton(
                    key: const Key('gameplay-history-import'),
                    onPressed: enabled ? _import : null,
                    child: Text(text('checkImport')),
                  ),
                ),
              ],
            ],
          ],
        ),
      );
    },
  );
}

class _GameplaySwitch extends StatelessWidget {
  const _GameplaySwitch({
    required this.label,
    required this.value,
    required this.controlKey,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final Key controlKey;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      SizedBox(width: context.tokens.space.sm),
      Semantics(
        label: label,
        child: Switch(key: controlKey, value: value, onChanged: onChanged),
      ),
    ],
  );
}

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog({required this.controller, required this.preview});
  final GameplayTimeController controller;
  final GameplayHistoryPreview preview;
  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (!identical(widget.controller.value.preview, widget.preview) &&
        !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        }
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.value;
    if (!identical(state.preview, widget.preview)) {
      return const SizedBox.shrink();
    }
    final strings = AppStrings.of(context);
    String text(String key) => strings.text('gameplay.$key');
    final preview = widget.preview;
    return PopScope(
      canPop: !state.busy,
      child: AlertDialog(
        key: const Key('gameplay-history-preview'),
        scrollable: true,
        title: Text(text('previewTitle')),
        content: SizedBox(
          width: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                gameplayDuration(strings, preview.seconds),
                key: const Key('gameplay-history-preview-duration'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: context.tokens.space.sm),
              Text(
                text('previewCounts')
                    .replaceAll('{sessions}', '${preview.sessions}')
                    .replaceAll('{incomplete}', '${preview.incompleteSessions}')
                    .replaceAll('{skipped}', '${preview.skippedFiles}'),
              ),
              SizedBox(height: context.tokens.space.md),
              Text(text('previewCaveat')),
              SizedBox(height: context.tokens.space.sm),
              Text(text('previewOnce')),
              if (state.historyError != null) ...[
                SizedBox(height: context.tokens.space.sm),
                Text(
                  text('history.${state.historyError}'),
                  style: TextStyle(color: context.tokens.colors.warning),
                ),
              ],
              if (state.busy) ...[
                SizedBox(height: context.tokens.space.md),
                const LinearProgressIndicator(),
                Text(text('confirming')),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('gameplay-history-cancel'),
            onPressed: state.busy ? null : () => Navigator.of(context).pop(),
            child: Text(text('cancel')),
          ),
          FilledButton(
            key: const Key('gameplay-history-confirm'),
            onPressed: state.busy
                ? null
                : () => widget.controller.confirmHistory(preview),
            child: Text(
              text(state.historyError == null ? 'confirm' : 'retryConfirm'),
            ),
          ),
        ],
      ),
    );
  }
}
