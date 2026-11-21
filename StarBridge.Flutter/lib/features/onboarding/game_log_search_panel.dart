import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'onboarding_copy.dart';
import 'onboarding_models.dart';

/// Shared presentation for guide, usage mode and local settings. Selection is explicit.
class GameLogSearchPanel extends StatefulWidget {
  const GameLogSearchPanel({
    required this.copy,
    required this.candidates,
    required this.busy,
    required this.enabled,
    required this.onSelect,
    required this.onManual,
    required this.onSearch,
    this.onEnter,
    this.searchEnabled = true,
    this.blocked = false,
    required this.manualKey,
    required this.searchKey,
    this.extra = const [],
    super.key,
  });
  final OnboardingCopy copy;
  final List<OnboardingLogCandidate>? candidates;
  final bool busy, enabled, searchEnabled;

  /// The last search stopped on a slow disk: never shown as "nothing found".
  final bool blocked;
  final Future<void> Function(int) onSelect;
  final Future<void> Function() onManual, onSearch;
  final Future<void> Function()? onEnter;
  final Key manualKey, searchKey;
  final List<Widget> extra;
  @override
  State<GameLogSearchPanel> createState() => _GameLogSearchPanelState();
}

class _GameLogSearchPanelState extends State<GameLogSearchPanel> {
  void _enter() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.enabled && widget.searchEnabled && !widget.busy) {
      unawaited(widget.onEnter?.call());
    }
  });
  @override
  void initState() {
    super.initState();
    _enter();
  }

  @override
  void didUpdateWidget(GameLogSearchPanel old) {
    super.didUpdateWidget(old);
    _enter();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget, copy = widget.copy, t = context.tokens;
    final items = w.candidates ?? const <OnboardingLogCandidate>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            copy.text(
              w.busy
                  ? 'checking'
                  : items.isNotEmpty
                  ? 'logSearch.found'
                  : w.blocked
                  ? 'logSearch.blocked'
                  : w.candidates == null
                  ? 'notChecked'
                  : 'logSearch.empty',
            ),
          ),
        ),
        if (!w.busy && w.blocked && items.isNotEmpty)
          Text(copy.text('logSearch.blocked')),
        for (var i = 0; i < items.length; i++)
          if (items.length == 1) ...[
            SizedBox(height: t.space.md),
            Text(items[i].version),
            Text(items[i].path),
            StarBridgeActionButton(
              controlKey: const Key('game-log-use-candidate'),
              kind: StarBridgeActionKind.primary,
              onActivate: w.enabled && w.searchEnabled
                  ? (_) => unawaited(w.onSelect(i))
                  : null,
              child: Text(copy.text('logSearch.use')),
            ),
          ] else ...[
            SizedBox(height: t.space.md),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(items[i].version), Text(items[i].path)],
                  ),
                ),
                SizedBox(width: t.space.md),
                StarBridgeActionButton(
                  controlKey: Key('game-log-candidate-$i'),
                  kind: StarBridgeActionKind.secondary,
                  onActivate: w.enabled && w.searchEnabled
                      ? (_) => unawaited(w.onSelect(i))
                      : null,
                  child: Text(copy.text('logSearch.use')),
                ),
              ],
            ),
          ],
        SizedBox(height: t.space.md),
        Wrap(
          spacing: t.space.md,
          runSpacing: t.space.sm,
          children: [
            StarBridgeActionButton(
              controlKey: w.manualKey,
              kind: StarBridgeActionKind.secondary,
              onActivate: w.enabled ? (_) => unawaited(w.onManual()) : null,
              child: Text(
                copy.text(items.isNotEmpty ? 'logSearch.other' : 'pickLog'),
              ),
            ),
            StarBridgeActionButton(
              controlKey: w.searchKey,
              kind: StarBridgeActionKind.quiet,
              onActivate: w.enabled && w.searchEnabled
                  ? (_) => unawaited(w.onSearch())
                  : null,
              child: Text(copy.text('logSearch.again')),
            ),
          ],
        ),
        ...w.extra,
      ],
    );
  }
}
