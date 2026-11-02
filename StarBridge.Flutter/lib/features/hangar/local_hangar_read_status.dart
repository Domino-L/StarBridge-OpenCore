import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../settings/help_support_waiting.dart';
import 'local_hangar_port.dart';
import 'local_hangar_copy.dart';
import 'hangar_read_diagnostics.dart';

/// Read status presentation; all IO and failure classification stay in owners.
class LocalHangarReadStatus extends StatelessWidget {
  const LocalHangarReadStatus({
    required this.snapshot,
    required this.saved,
    required this.loading,
    required this.favoriteBusy,
    required this.favoriteFailed,
    required this.failed,
    required this.onRetry,
    this.readSource = InteractionSource.programmatic,
    this.favoriteSource = InteractionSource.programmatic,
    this.readPhase = 0,
    this.favoritePhase = 0,
    this.inheritReadOpeningSource = true,
    super.key,
  });
  final LocalHangarSnapshot? snapshot;
  final bool saved, loading, favoriteBusy, favoriteFailed, failed;
  final VoidCallback onRetry;
  final InteractionSource readSource, favoriteSource;
  final int readPhase, favoritePhase;
  final bool inheritReadOpeningSource;
  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (saved)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StarBridgeTooltip(
              message: snapshot!.partial ? c.partial : '',
              child: Text(
                snapshot!.fromLegacyProfile
                    ? c.legacySource
                    : c.savedOn(context, snapshot!.inventoryReadSavedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        if (loading)
          KeyedSubtree(
            key: const Key('hangar-refresh-progress'),
            child: _HangarWaiting(
              key: ValueKey(('hangar-read-wait', readPhase)),
              label: snapshot == null ? c.loading : c.refreshing,
              source: readSource,
              inheritOpeningSource: inheritReadOpeningSource,
            ),
          ),
        if (saved && snapshot!.partial)
          Semantics(
            liveRegion: true,
            child: Text(
              c.partial,
              key: const Key('hangar-partial-warning'),
              style: TextStyle(color: tokens.colors.warning),
            ),
          ),
        if (favoriteBusy)
          _HangarWaiting(
            key: ValueKey(('hangar-favorite-wait', favoritePhase)),
            label: c.updatingFavorite,
            source: favoriteSource,
            inheritOpeningSource: false,
            showNativeLabel: false,
          ),
        if (favoriteFailed)
          Semantics(
            liveRegion: true,
            child: Text(
              c.favoriteFailure,
              style: TextStyle(color: tokens.colors.warning),
            ),
          ),
        if (failed)
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.readFailure,
                  style: TextStyle(color: tokens.colors.warning),
                ),
                StarBridgeActionButton(
                  controlKey: const Key('local-hangar-retry'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (_) => onRetry(),
                  child: Text(c.retry),
                ),
                if (HangarReadDiagnostics.enabled)
                  SelectableText(
                    'DIAGNOSTIC BUILD — NOT FOR RELEASE\n'
                    '${HangarReadDiagnostics.entries.join('\n')}',
                    key: const Key('hangar-read-diagnostics'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Retain a phase's provenance even when the user changes suite while waiting.
/// This owns decoration only, never request admission or completion.
class _HangarWaiting extends StatefulWidget {
  const _HangarWaiting({
    required this.source,
    required this.label,
    required this.inheritOpeningSource,
    this.showNativeLabel = true,
    super.key,
  });
  final InteractionSource source;
  final String label;
  final bool inheritOpeningSource, showNativeLabel;

  @override
  State<_HangarWaiting> createState() => _HangarWaitingState();
}

class _HangarWaitingState extends State<_HangarWaiting> {
  InteractionSource? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _source ??= widget.inheritOpeningSource
        ? resolveStarBridgeInitialReadSource(context, widget.source)
        : widget.source;
  }

  @override
  Widget build(BuildContext context) {
    final data = resolveStarBridgeInteraction(context);
    if (data.suite != InteractionSuite.standard) {
      return HelpSupportWaiting(
        label: widget.label,
        source: _source!,
        inheritOpeningSource: false,
      );
    }
    return Semantics(
      liveRegion: true,
      label: widget.label,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showNativeLabel) Text(widget.label),
            if (data.reduceMotion || _source == InteractionSource.keyboard)
              SizedBox(
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.tokens.colors.accentSoft,
                  ),
                ),
              )
            else
              const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
