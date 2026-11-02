import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_statistics_controller.dart';
import 'onboarding_copy.dart';

class LocalStatisticsPanel extends StatefulWidget {
  const LocalStatisticsPanel({
    required this.copy,
    required this.enabled,
    this.interactionBlocked = false,
    this.controller,
    this.onChanged,
    super.key,
  });
  final OnboardingCopy copy;
  final bool enabled;
  final bool interactionBlocked;
  final LocalStatisticsController? controller;
  final Future<void> Function()? onChanged;
  @override
  State<LocalStatisticsPanel> createState() => _LocalStatisticsPanelState();
}

class _LocalStatisticsPanelState extends State<LocalStatisticsPanel> {
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(LocalStatisticsPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller || old.enabled != widget.enabled) {
      _read();
    }
  }

  void _read() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.enabled) {
      widget.controller?.refresh();
    }
  });
  Future<void> _run(Future<void> Function() run) async {
    await run();
    if (mounted) {
      await widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.controller?.value ?? const LocalStatisticsView();
    final copy = widget.copy;
    final t = context.tokens;
    final canEdit =
        widget.enabled &&
        !widget.interactionBlocked &&
        !view.busy &&
        !view.error &&
        view.snapshot.canChoose;
    final selected = view.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          copy.text('statistics.title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: t.space.sm),
        Text(copy.text('statistics.intro')),
        SizedBox(height: t.space.md),
        Semantics(
          liveRegion: true,
          child: Text(
            copy.text(
              view.busy
                  ? 'busy'
                  : view.error
                  ? 'statistics.error'
                  : view.snapshot.choiceSaved
                  ? 'statistics.${view.snapshot.consent.name}'
                  : 'statistics.state.${view.snapshot.state.name}',
            ),
            style: TextStyle(
              color: view.snapshot.choiceSaved && !view.error
                  ? t.colors.success
                  : t.colors.textSecondary,
            ),
          ),
        ),
        if (view.snapshot.savedSeconds case final seconds?) ...[
          SizedBox(height: t.space.sm),
          Text(
            '${copy.text('statistics.savedTime')} · ${seconds ~/ 60} ${copy.text('statistics.minutes')}',
          ),
        ],
        SizedBox(height: t.space.md),
        RadioGroup<bool>(
          groupValue: selected,
          onChanged: (value) {
            if (value != null && canEdit) {
              widget.controller!.select(value);
            }
          },
          child: Column(
            children: [
              RadioListTile<bool>(
                key: const Key('statistics-allow'),
                value: true,
                enabled: canEdit,
                title: Text(copy.text('statistics.allow')),
                subtitle: Text(copy.text('statistics.allowBody')),
              ),
              RadioListTile<bool>(
                key: const Key('statistics-decline'),
                value: false,
                enabled: canEdit,
                title: Text(copy.text('statistics.decline')),
                subtitle: Text(copy.text('statistics.declineBody')),
              ),
            ],
          ),
        ),
        SizedBox(height: t.space.sm),
        Wrap(
          spacing: t.space.md,
          runSpacing: t.space.sm,
          children: [
            StarBridgeActionButton(
              controlKey: const Key('statistics-confirm'),
              kind: StarBridgeActionKind.primary,
              onActivate: _tap(
                widget.enabled && !widget.interactionBlocked && view.canConfirm
                    ? () => _run(widget.controller!.confirm)
                    : null,
              ),
              child: Text(copy.text('statistics.confirm')),
            ),
            StarBridgeActionButton(
              controlKey: const Key('statistics-refresh'),
              kind: StarBridgeActionKind.quiet,
              onActivate: _tap(
                !widget.interactionBlocked &&
                        !view.busy &&
                        widget.controller != null
                    ? () => _run(widget.controller!.refresh)
                    : null,
              ),
              child: Text(copy.text('retry')),
            ),
          ],
        ),
        SizedBox(height: t.space.md),
        Text(copy.text('statistics.separate')),
      ],
    );
  }
}

/// Native-style tap callback to a suite activation (source unused here).
ValueChanged<InteractionSource>? _tap(VoidCallback? onPressed) =>
    onPressed == null ? null : (_) => onPressed();
