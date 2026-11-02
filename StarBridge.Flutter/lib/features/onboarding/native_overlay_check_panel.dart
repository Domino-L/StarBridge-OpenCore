import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'native_overlay_check_controller.dart';
import 'onboarding_copy.dart';

/// One original Native preview entry and one deliberate, bounded input check.
/// No checkbox, generated keypress, saved choice, or S4 readiness surrogate.
class NativeOverlayCheckPanel extends StatefulWidget {
  const NativeOverlayCheckPanel({
    required this.controller,
    required this.copy,
    this.enabled = false,
    this.interactionBlocked = false,
    this.openPreview,
    super.key,
  });
  final NativeOverlayCheckController controller;
  final OnboardingCopy copy;
  final bool enabled;
  final bool interactionBlocked;
  final Future<void> Function()? openPreview;

  @override
  State<NativeOverlayCheckPanel> createState() =>
      _NativeOverlayCheckPanelState();
}

class _NativeOverlayCheckPanelState extends State<NativeOverlayCheckPanel> {
  @override
  void initState() {
    super.initState();
    _read();
  }

  void _read() {
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled && controller == widget.controller) {
        unawaited(controller.refresh());
      }
    });
  }

  @override
  void didUpdateWidget(NativeOverlayCheckPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => oldWidget.controller.suspend(),
      );
      _read();
    } else if (!oldWidget.enabled && widget.enabled) {
      _read();
    } else if (oldWidget.enabled && !widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.enabled) widget.controller.suspend();
      });
    }
  }

  @override
  void dispose() {
    scheduleMicrotask(widget.controller.stopHotkeyCheck);
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<NativeOverlayCheckView>(
    valueListenable: widget.controller,
    builder: (context, view, _) {
      final t = context.tokens, copy = widget.copy;
      final observation = view.observation;
      final ready = widget.enabled && !widget.interactionBlocked && !view.busy;
      final hotkeyState = view.hotkey == NativeHotkeyCheck.notStarted
          ? observation == null
                ? 'unavailable'
                : 'hotkey.${observation.hotkey.state}'
          : 'check.${view.hotkey.name}';
      return Container(
        key: const Key('onboarding-native-checks'),
        padding: EdgeInsets.all(t.space.md),
        decoration: BoxDecoration(
          borderRadius: t.shape.small,
          border: Border.all(color: t.surfaces.panel.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                copy.text('native.title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SizedBox(height: t.space.sm),
            Text(copy.text('native.intro')),
            SizedBox(height: t.space.lg),
            Text(copy.text('native.previewTitle')),
            SizedBox(height: t.space.xs),
            Semantics(
              liveRegion: true,
              child: Text(copy.text('native.preview.${view.preview.name}')),
            ),
            SizedBox(height: t.space.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StarBridgeActionButton(
                controlKey: const Key('native-open-preview'),
                kind: StarBridgeActionKind.secondary,
                onActivate: _tap(
                  ready && widget.openPreview != null
                      ? () =>
                            widget.controller.visitPreview(widget.openPreview!)
                      : null,
                ),
                child: Text(copy.text('native.openPreview')),
              ),
            ),
            SizedBox(height: t.space.md),
            Divider(color: t.surfaces.panel.border),
            SizedBox(height: t.space.md),
            Text(copy.text('native.hotkeyTitle')),
            SizedBox(height: t.space.xs),
            if (observation?.hotkey.binding case final binding?)
              Text(binding, style: Theme.of(context).textTheme.titleLarge),
            Semantics(
              liveRegion: true,
              child: Text(copy.text('native.$hotkeyState')),
            ),
            if (view.hotkey == NativeHotkeyCheck.observed)
              if (observation?.hotkey.lastOutcome case final outcome?)
                Text(
                  copy.text('native.outcome.$outcome'),
                  style: TextStyle(
                    color: outcome == 'failed' || outcome == 'unavailable'
                        ? t.colors.warning
                        : t.colors.textPrimary,
                  ),
                ),
            SizedBox(height: t.space.sm),
            Text(copy.text('native.hotkeyHelp')),
            SizedBox(height: t.space.sm),
            Wrap(
              spacing: t.space.md,
              runSpacing: t.space.sm,
              children: [
                if (view.hotkey == NativeHotkeyCheck.waiting)
                  StarBridgeActionButton(
                    controlKey: const Key('native-stop-check'),
                    kind: StarBridgeActionKind.secondary,
                    onActivate: _tap(widget.controller.stopHotkeyCheck),
                    child: Text(copy.text('native.stopCheck')),
                  )
                else
                  StarBridgeActionButton(
                    controlKey: const Key('native-start-check'),
                    kind: StarBridgeActionKind.secondary,
                    onActivate: _tap(
                      widget.enabled &&
                              !widget.interactionBlocked &&
                              view.canCheckHotkey
                          ? widget.controller.startHotkeyCheck
                          : null,
                    ),
                    child: Text(copy.text('native.startCheck')),
                  ),
                StarBridgeActionButton(
                  controlKey: const Key('native-refresh'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: _tap(ready ? widget.controller.refresh : null),
                  child: Text(copy.text('retry')),
                ),
              ],
            ),
            if (view.readError) ...[
              SizedBox(height: t.space.sm),
              Text(copy.text('native.readError')),
            ],
            SizedBox(height: t.space.md),
            Text(
              copy.text('native.optional'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: t.colors.textSecondary),
            ),
          ],
        ),
      );
    },
  );
}

/// Native-style tap callback to a suite activation (source unused here).
ValueChanged<InteractionSource>? _tap(VoidCallback? onPressed) =>
    onPressed == null ? null : (_) => onPressed();
