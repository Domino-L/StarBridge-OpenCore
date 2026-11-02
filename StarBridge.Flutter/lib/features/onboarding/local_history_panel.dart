import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_history_controller.dart';
import 'local_history_port.dart';
import 'onboarding_copy.dart';

String formatHistoryDuration(OnboardingCopy copy, int seconds) {
  final minutes = (seconds / 60).round();
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return hours == 0
      ? '$rest ${copy.text('history.minutes')}'
      : '$hours ${copy.text('history.hours')} $rest ${copy.text('history.minutes')}';
}

/// Optional, explicit history import for the confirmed local profile.
class LocalHistoryPanel extends StatefulWidget {
  const LocalHistoryPanel({
    required this.copy,
    required this.controller,
    required this.enabled,
    this.interactionBlocked = false,
    this.onReset,
    super.key,
  });
  final OnboardingCopy copy;
  final LocalHistoryController controller;
  final bool enabled;
  final bool interactionBlocked;

  /// Called after a confirmed reset so other panels re-read saved time.
  final Future<void> Function()? onReset;
  @override
  State<LocalHistoryPanel> createState() => _LocalHistoryPanelState();
}

class _LocalHistoryPanelState extends State<LocalHistoryPanel> {
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(LocalHistoryPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller || old.enabled != widget.enabled) {
      _read();
    }
  }

  void _read() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.enabled) widget.controller.refresh();
  });

  Future<bool> _confirmReset(
    LocalResetSnapshot preview,
    InteractionSource source,
  ) async {
    final copy = widget.copy;
    final t = context.tokens;
    final total = formatHistoryDuration(copy, preview.seconds ?? 0);
    final history = formatHistoryDuration(copy, preview.historicalSeconds ?? 0);
    final confirmed = await showStarBridgeDialog<bool>(
      context,
      source: source,
      builder: (context) => AlertDialog(
        key: const Key('history-reset-dialog'),
        title: Text(copy.text('history.reset.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy
                  .text('history.reset.body')
                  .replaceAll('{total}', total)
                  .replaceAll('{history}', history),
            ),
            SizedBox(height: t.space.sm),
            Text(copy.text('history.reset.detail')),
            SizedBox(height: t.space.sm),
            Text(
              copy.text('history.reset.backup'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          StarBridgeActionButton(
            controlKey: const Key('history-reset-keep'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: false),
            child: Text(copy.text('history.reset.keep')),
          ),
          StarBridgeActionButton(
            controlKey: const Key('history-reset-confirm'),
            kind: StarBridgeActionKind.primary,
            nativeStyle: FilledButton.styleFrom(
              backgroundColor: t.colors.danger,
            ),
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: true),
            child: Text(copy.text('history.reset.confirm')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _reset(InteractionSource source) async {
    await widget.controller.reset((preview) => _confirmReset(preview, source));
    if (mounted && widget.controller.value.reset == LocalResetResult.done) {
      await widget.onReset?.call();
    }
  }

  String _status(LocalHistoryView view) {
    final copy = widget.copy;
    final s = view.snapshot;
    return switch (s.state) {
      LocalHistoryState.imported =>
        copy
            .text('history.imported')
            .replaceAll(
              '{duration}',
              formatHistoryDuration(copy, s.importedSeconds ?? 0),
            )
            .replaceAll(
              '{date}',
              MaterialLocalizations.of(context)
                  .formatMediumDate(s.importedAt!.toLocal()),
            ),
      LocalHistoryState.scanning =>
        copy
            .text(
              s.phase == 'cancelling'
                  ? 'history.cancelling'
                  : 'history.scanning',
            )
            .replaceAll('{done}', '${s.processedFiles}')
            .replaceAll('{total}', '${s.totalFiles}'),
      LocalHistoryState.preview =>
        copy
            .text('history.preview')
            .replaceAll('{sessions}', '${s.sessions}')
            .replaceAll('{duration}', formatHistoryDuration(copy, s.seconds!)),
      final state => copy.text('history.state.${state.name}'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final t = context.tokens;
    return ValueListenableBuilder<LocalHistoryView>(
      valueListenable: widget.controller,
      builder: (context, view, _) {
        final s = view.snapshot;
        final active = widget.enabled && !widget.interactionBlocked;
        final notes = <String>[
          if (s.state == LocalHistoryState.preview) ...[
            if (s.incompleteSessions > 0)
              copy
                  .text('history.incomplete')
                  .replaceAll('{n}', '${s.incompleteSessions}'),
            if (s.skippedFiles > 0)
              copy
                  .text('history.skippedFiles')
                  .replaceAll('{n}', '${s.skippedFiles}'),
            copy.text('history.once'),
          ],
          if (view.lastResult case final result?)
            copy.text('history.result.${result.name}'),
          if (view.failure != LocalHistoryFailure.none)
            copy.text('history.failure.${view.failure.name}'),
          if (view.skipped && !view.imported) copy.text('history.skippedNote'),
          if (view.reset != LocalResetResult.none)
            copy.text('history.reset.result.${view.reset.name}'),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              copy.text('history.title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: t.space.sm),
            Text(copy.text('history.intro')),
            SizedBox(height: t.space.md),
            Semantics(
              liveRegion: true,
              child: Text(
                key: const Key('history-status'),
                _status(view),
                style: TextStyle(
                  color: view.imported
                      ? t.colors.success
                      : view.failure != LocalHistoryFailure.none
                      ? t.colors.warning
                      : t.colors.textSecondary,
                ),
              ),
            ),
            for (final note in notes) ...[
              SizedBox(height: t.space.xs),
              Text(note),
            ],
            if (s.state == LocalHistoryState.scanning && s.totalFiles > 0) ...[
              SizedBox(height: t.space.sm),
              LinearProgressIndicator(value: s.processedFiles / s.totalFiles),
            ],
            SizedBox(height: t.space.md),
            Wrap(
              spacing: t.space.md,
              runSpacing: t.space.sm,
              children: [
                if (s.state == LocalHistoryState.preview)
                  StarBridgeActionButton(
                    controlKey: const Key('history-confirm'),
                    kind: StarBridgeActionKind.primary,
                    onActivate: _tap(
                      active && view.canConfirm
                          ? widget.controller.confirm
                          : null,
                    ),
                    child: Text(copy.text('history.confirm')),
                  )
                else if (s.state == LocalHistoryState.scanning)
                  StarBridgeActionButton(
                    controlKey: const Key('history-cancel'),
                    kind: StarBridgeActionKind.secondary,
                    onActivate: _tap(
                      s.phase == 'cancelling' ? null : widget.controller.cancel,
                    ),
                    child: Text(copy.text('history.cancel')),
                  )
                else if (!view.imported)
                  StarBridgeActionButton(
                    controlKey: const Key('history-scan'),
                    kind: StarBridgeActionKind.secondary,
                    onActivate: _tap(
                      active && view.canScan ? widget.controller.scan : null,
                    ),
                    child: Text(copy.text('history.scan')),
                  ),
                if (!view.imported && !view.skipped)
                  StarBridgeActionButton(
                    controlKey: const Key('history-skip'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: _tap(
                      active && view.canSkip ? widget.controller.skip : null,
                    ),
                    child: Text(copy.text('history.skip')),
                  )
                else if (view.skipped && !view.imported)
                  StarBridgeActionButton(
                    controlKey: const Key('history-undo-skip'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: _tap(
                      active && !view.busy ? widget.controller.undoSkip : null,
                    ),
                    child: Text(copy.text('history.undoSkip')),
                  ),
                if (widget.controller.resetSupported &&
                    s.state != LocalHistoryState.scanning)
                  StarBridgeActionButton(
                    controlKey: const Key('history-reset'),
                    kind: StarBridgeActionKind.quiet,
                    nativeStyle: TextButton.styleFrom(
                      foregroundColor: t.colors.danger,
                    ),
                    onActivate: active && !view.busy ? _reset : null,
                    child: Text(copy.text('history.reset.open')),
                  ),
                if (s.state != LocalHistoryState.scanning)
                  StarBridgeActionButton(
                    controlKey: const Key('history-refresh'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: _tap(
                      active && !view.busy ? widget.controller.refresh : null,
                    ),
                    child: Text(copy.text('retry')),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Native-style tap callback to a suite activation (source unused here).
ValueChanged<InteractionSource>? _tap(VoidCallback? onPressed) =>
    onPressed == null ? null : (_) => onPressed();
