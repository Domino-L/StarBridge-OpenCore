import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import 'gameplay_time_controller.dart';

String gameplayDuration(AppStrings strings, int seconds) => strings
    .text('gameplay.duration')
    .replaceAll('{hours}', '${seconds ~/ 3600}')
    .replaceAll('{minutes}', '${seconds ~/ 60 % 60}');

class GameplayTimePanel extends StatefulWidget {
  const GameplayTimePanel({required this.controller, super.key});
  final GameplayTimeController controller;

  @override
  State<GameplayTimePanel> createState() => _GameplayTimePanelState();
}

class _GameplayTimePanelState extends State<GameplayTimePanel> {
  bool _dialogOpen = false;
  InteractionSource? _source;

  Future<void> _reset(InteractionSource source) async {
    if (_dialogOpen) return;
    _source = source;
    final controller = widget.controller;
    await controller.resetTime(() async {
      if (!mounted || controller != widget.controller || _dialogOpen) {
        return false;
      }
      _dialogOpen = true;
      try {
        return await showStarBridgeDialog<bool>(
              context,
              source: source,
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
                              route != null &&
                              route.isActive) {
                            Navigator.of(dialogContext)
                                .removeRoute(route, false);
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
                          StarBridgeActionButton(
                            kind: StarBridgeActionKind.quiet,
                            controlKey: const Key('gameplay-reset-keep'),
                            onActivate: (source) =>
                                dismissStarBridgeDialog<bool>(
                                  dialogContext,
                                  source: source,
                                  result: false,
                                ),
                            child: Text(text('keep')),
                          ),
                          StarBridgeActionButton(
                            kind: StarBridgeActionKind.quiet,
                            tone: ActionTone.danger,
                            controlKey: const Key('gameplay-reset-confirm'),
                            onActivate: (source) =>
                                dismissStarBridgeDialog<bool>(
                                  dialogContext,
                                  source: source,
                                  result: true,
                                ),
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

  Future<void> _import(InteractionSource source) async {
    if (_dialogOpen) return;
    _source = source;
    final controller = widget.controller;
    _dialogOpen = true;
    GameplayHistoryPreview? preview;
    try {
      final operation = controller.importHistory();
      if (controller.value.scanProgress != null) {
        await showStarBridgeDialog<void>(
          context,
          source: source,
          barrierDismissible: false,
          builder: (_) =>
              _HistoryScanDialog(controller: controller, source: source),
        );
      }
      await operation;
      if (!mounted || controller != widget.controller) return;
      preview = controller.value.preview;
      if (preview == null) return;
      final readyPreview = preview;
      await showStarBridgeDialog<void>(
        context,
        source: source,
        barrierDismissible: false,
        builder: (_) => _HistoryDialog(
          controller: controller,
          preview: readyPreview,
          source: source,
          onSourceChanged: (source) {
            if (mounted && controller == widget.controller) _source = source;
          },
        ),
      );
    } finally {
      _dialogOpen = false;
      if (preview != null) controller.cancelPreview(preview);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<GameplayTimeView>(
    valueListenable: widget.controller,
    builder: (context, state, _) {
      if (!state.visible) return const SizedBox.shrink();
      final controller = widget.controller;
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
          : error == 'identityUnconfirmed'
          ? 'identityError'
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
              child: StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('gameplay-time-explanation'),
                onActivate: (source) => showStarBridgeDialog<void>(
                  context,
                  source: source,
                  builder: (dialogContext) => AlertDialog(
                    scrollable: true,
                    title: Text(text('explanationTitle')),
                    content: Text(text('explanationBody')),
                    actions: [
                      StarBridgeActionButton(
                        kind: StarBridgeActionKind.quiet,
                        controlKey: const Key(
                          'gameplay-time-explanation-close',
                        ),
                        onActivate: (source) => dismissStarBridgeDialog<void>(
                          dialogContext,
                          source: source,
                        ),
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
              onChanged: enabled
                  ? (value) {
                      _source = currentStarBridgeActivationSource;
                      controller.setAllowed(value);
                    }
                  : null,
            ),
            if (state.historySupported)
              _GameplaySwitch(
                label: text('profileSwitch'),
                value: state.showOnProfile,
                controlKey: const Key('gameplay-time-profile-switch'),
                onChanged: enabled
                    ? (value) {
                        _source = currentStarBridgeActivationSource;
                        controller.setVisibility(value);
                      }
                    : null,
              ),
            if (state.busy && state.operation != 'resetConfirmation') ...[
              SizedBox(height: tokens.space.sm),
              _GameplayWaiting(
                key: const Key('gameplay-time-busy'),
                source:
                    _source ??
                    resolveStarBridgeInitialReadSource(
                      context,
                      InteractionSource.programmatic,
                    ),
              ),
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
                child: StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('gameplay-time-retry'),
                  onActivate: enabled
                      ? (source) {
                          _source = source;
                          controller.retry();
                        }
                      : null,
                  child: Text(text('retry')),
                ),
              ),
            if (widget.controller.resetSupported) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('gameplay-reset-open'),
                  onActivate: enabled && state.resetState != 'pending'
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
                  child: StarBridgeActionButton(
                    controlKey: const Key('gameplay-history-import'),
                    onActivate: enabled ? _import : null,
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
  Widget build(BuildContext context) => StarBridgeSwitch.tile(
    label: label,
    value: value,
    onChanged: onChanged,
    controlKey: controlKey,
    rowBuilder: (control) => Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(width: context.tokens.space.sm),
        control,
      ],
    ),
  );
}

class _HistoryScanDialog extends StatefulWidget {
  const _HistoryScanDialog({required this.controller, required this.source});
  final GameplayTimeController controller;
  final InteractionSource source;
  @override
  State<_HistoryScanDialog> createState() => _HistoryScanDialogState();
}

class _HistoryScanDialogState extends State<_HistoryScanDialog> {
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (widget.controller.value.scanProgress == null && !_closing) {
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
    final scan = widget.controller.value.scanProgress;
    if (scan == null) return const SizedBox.shrink();
    String text(String key) =>
        AppStrings.of(context).text('gameplay.scan.$key');
    final cancelling = scan.phase == 'cancelling';
    final known = scan.phase == 'scanning' && scan.totalBytes > 0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            widget.controller.cancelHistoryScan,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) widget.controller.cancelHistoryScan();
          },
          child: AlertDialog(
            key: const Key('gameplay-history-scan'),
            scrollable: true,
            title: Text(text('title')),
            content: SizedBox(
              width: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    text(scan.phase),
                    key: const Key('gameplay-history-scan-phase'),
                  ),
                  SizedBox(height: context.tokens.space.md),
                  _GameplayWaiting(
                    source: widget.source,
                    value: known ? scan.readBytes / scan.totalBytes : null,
                  ),
                  SizedBox(height: context.tokens.space.md),
                  Text(
                    text('files')
                        .replaceAll('{done}', '${scan.processedFiles}')
                        .replaceAll('{total}', '${scan.totalFiles}'),
                    key: const Key('gameplay-history-scan-files'),
                  ),
                  if (known)
                    Text(
                      text('bytes')
                          .replaceAll(
                            '{read}',
                            (scan.readBytes / 1048576).toStringAsFixed(1),
                          )
                          .replaceAll(
                            '{total}',
                            (scan.totalBytes / 1048576).toStringAsFixed(1),
                          ),
                    ),
                  SizedBox(height: context.tokens.space.md),
                  Text(text('notice')),
                ],
              ),
            ),
            actions: [
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                controlKey: const Key('gameplay-history-scan-cancel'),
                onActivate: cancelling
                    ? null
                    : (_) => widget.controller.cancelHistoryScan(),
                child: Text(text(cancelling ? 'cancelling' : 'cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog({
    required this.controller,
    required this.preview,
    required this.source,
    required this.onSourceChanged,
  });
  final GameplayTimeController controller;
  final GameplayHistoryPreview preview;
  final InteractionSource source;
  final ValueChanged<InteractionSource> onSourceChanged;
  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  bool _closing = false;
  late InteractionSource _source = widget.source;
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
                _GameplayWaiting(source: _source),
                Text(text('confirming')),
              ],
            ],
          ),
        ),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('gameplay-history-cancel'),
            onActivate: state.busy
                ? null
                : (source) =>
                      dismissStarBridgeDialog<void>(context, source: source),
            child: Text(text('cancel')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: const Key('gameplay-history-confirm'),
            onActivate: state.busy
                ? null
                : (source) {
                    _source = source;
                    widget.onSourceChanged(source);
                    widget.controller.confirmHistory(preview);
                  },
            child: Text(
              text(state.historyError == null ? 'confirm' : 'retryConfirm'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameplayWaiting extends StatelessWidget {
  const _GameplayWaiting({required this.source, this.value, super.key});
  final InteractionSource source;
  final double? value;
  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        return InteractionScope(
          data: data.copyWith(
            reduceMotion:
                data.reduceMotion || source == InteractionSource.keyboard,
          ),
          child: SuiteProgressBar(value: value, phase: ProgressPhase.running),
        );
      },
    ),
  );
}
