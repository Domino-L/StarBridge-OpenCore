import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_activation_origin.dart';
import 'starbridge_interaction_theme.dart';
import 'starbridge_tooltip.dart';
import 'starbridge_native_ink.dart';

/// Native-layout icon presentation. The caller retains geometry, colours and
/// the synchronous command; no pending state, protocol or business owner here.
/// Keep Material's layout in every suite so native hit-testing does not drift.
class StarBridgeNativeIconAction extends StatefulWidget {
  const StarBridgeNativeIconAction({
    required this.label,
    required this.icon,
    this.semanticLabel,
    this.style = const ButtonStyle(),
    this.onActivate,
    this.padding,
    this.iconSize,
    this.constraints,
    this.focusNode,
    this.autofocus = false,
    this.selected,
    this.controlKey,
    this.onHintVisibilityChanged,
    this.consumeHintEscape = true,
    super.key,
  });

  final String label;

  /// Optional richer reader text; the tooltip keeps [label] unchanged.
  final String? semanticLabel;
  final Widget icon;
  final ButtonStyle style;
  final ValueChanged<InteractionSource>? onActivate;
  final EdgeInsetsGeometry? padding;
  final double? iconSize;
  final BoxConstraints? constraints;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool? selected;
  final Key? controlKey;
  final ValueChanged<bool>? onHintVisibilityChanged;
  final bool consumeHintEscape;

  @override
  State<StarBridgeNativeIconAction> createState() => _NativeIconActionState();
}

class _NativeIconActionState extends State<StarBridgeNativeIconAction> {
  final _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  final _effect = GlobalKey<EffectHostState>();
  final _ink = StarBridgeNativeInk();
  InteractionSource _source = InteractionSource.keyboard;
  Offset? _pointer;

  void _activate(BuildContext context, InteractionSource source) {
    _source = InteractionSource.keyboard;
    final action = widget.onActivate;
    if (action == null) return;
    final data = InteractionScope.of(context);
    final fx = _effect.currentState;
    if (source != InteractionSource.pointer) {
      fx?.clear();
      // Material ink is not owned by EffectHost. Retire a preceding pointer's
      // splash too, retaining the same focus node and synchronous command.
      if (data.suite == InteractionSuite.standard && !data.reduceMotion) {
        _ink.retire();
      }
    } else if (data.animates) {
      switch (data.suite) {
        case InteractionSuite.rail:
          fx?.play(TransientEffect.sweep);
        case InteractionSuite.scan:
          fx?.play(TransientEffect.bracketFlash);
          fx?.play(TransientEffect.beam);
        case InteractionSuite.glow:
          fx?.play(TransientEffect.ring, at: _pointer, ringScale: 2);
        case InteractionSuite.standard:
          break;
      }
    }
    // Do not await, defer, deduplicate or catch the caller's window command.
    runStarBridgeSynchronousActivation(source, () => action(source));
  }

  @override
  void dispose() {
    _ink.dispose();
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: ListenableBuilder(
      listenable: _focus,
      builder: (context, _) => _build(context),
    ),
  );

  Widget _build(BuildContext context) {
    final data = InteractionScope.of(context);
    final nativeInk =
        data.suite == InteractionSuite.standard && !data.reduceMotion;
    final enabled = widget.onActivate != null;
    final style = _ink.resolveStyle(
      context,
      animated: nativeInk,
      style: widget.style,
      themeStyle: IconButtonTheme.of(context).style,
    );
    // The action belongs to the viewport, not the passive hint's portal.
    return Semantics(
      container: true,
      label: widget.semanticLabel ?? widget.label,
      button: true,
      toggled: widget.selected,
      enabled: enabled,
      focusable: enabled,
      focused: enabled ? _focus.hasFocus : null,
      excludeSemantics: true,
      onTap: enabled
          ? () => _activate(context, InteractionSource.keyboard)
          : null,
      child: StarBridgeTooltip(
        message: widget.label,
        excludeFromSemantics: true,
        onVisibilityChanged: widget.onHintVisibilityChanged,
        consumeEscape: widget.consumeHintEscape,
        // Clip paint only; the original Material hit rectangle stays intact.
        child: ClipRect(
          child: EffectHost(
            key: _effect,
            child: CallbackShortcuts(
              bindings: {
                for (final key in [
                  LogicalKeyboardKey.enter,
                  LogicalKeyboardKey.numpadEnter,
                  LogicalKeyboardKey.space,
                ])
                  SingleActivator(key): () =>
                      _activate(context, InteractionSource.keyboard),
              },
              child: Listener(
                onPointerDown: (event) {
                  _source = InteractionSource.pointer;
                  _pointer = event.localPosition;
                },
                onPointerCancel: (_) => _source = InteractionSource.keyboard,
                // Keep the recognizer alive when reduce changes mid-press.
                // Only owned ink features retire, never the pending gesture.
                child: IconButton(
                  key: widget.controlKey,
                  focusNode: _focus,
                  statesController: _ink.states,
                  autofocus: widget.autofocus,
                  isSelected: widget.selected,
                  constraints: widget.constraints,
                  padding: widget.padding,
                  iconSize: widget.iconSize,
                  style: style,
                  onPressed: enabled ? () => _activate(context, _source) : null,
                  icon: widget.icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
