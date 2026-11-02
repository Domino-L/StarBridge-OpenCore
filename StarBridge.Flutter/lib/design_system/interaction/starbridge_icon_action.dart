import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../tokens/color_tokens.dart';
import '../tokens/starbridge_tokens.dart';
import 'starbridge_interaction_theme.dart';
import 'starbridge_tooltip.dart';
import 'starbridge_activation_origin.dart';
import 'starbridge_native_icon_action.dart';

/// An icon target, not a value owner. [selected] is only the caller's confirmed
/// state; presses never set it optimistically or delay the original command.
/// Accepts painted StarBridge glyphs instead of substituting Material icons.
class StarBridgeIconAction extends StatefulWidget {
  const StarBridgeIconAction({
    required this.icon,
    required this.label,
    this.onActivate,
    this.selected,
    this.controlKey,
    this.focusNode,
    this.autofocus = false,
    this.constraints,
    this.padding,
    this.consumeHintEscape = true,
    this.quiet = false,
    super.key,
  });

  final Widget icon;
  final String label;
  final ValueChanged<InteractionSource>? onActivate;
  final bool? selected;
  final Key? controlKey;
  final FocusNode? focusNode;
  final bool autofocus;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;

  /// No frame or fill at rest and a secondary glyph; hover, focus and press
  /// bring the ordinary face back. For actions beside a value.
  final bool quiet;

  /// A passive hint in a modal may let the same Escape reach its owner.
  final bool consumeHintEscape;

  @override
  State<StarBridgeIconAction> createState() => _StarBridgeIconActionState();
}

class _StarBridgeIconActionState extends State<StarBridgeIconAction> {
  final _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;

  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  void _activate(InteractionSource source) {
    unawaited(
      runStarBridgeActivation<void>(
        source,
        () => widget.onActivate?.call(source),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      StarBridgeInteractionRegion(child: Builder(builder: _buildControl));

  static ButtonStyle _quietStyle(ColorTokens colors) {
    bool lit(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused) ||
        states.contains(WidgetState.pressed);
    return ButtonStyle(
      side: WidgetStateProperty.resolveWith(
        (states) => lit(states)
            ? null
            : BorderSide(color: colors.textPrimary.withValues(alpha: 0)),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            lit(states) ? null : colors.textPrimary.withValues(alpha: 0),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => lit(states) ? colors.textPrimary : colors.textSecondary,
      ),
    );
  }

  Widget _buildControl(BuildContext context) {
    final data = InteractionScope.of(context);
    final enabled = widget.onActivate != null;
    final Widget control;
    if (data.suite == InteractionSuite.standard) {
      final quietStyle = !widget.quiet
          ? const ButtonStyle()
          : _quietStyle(context.tokens.colors);
      return StarBridgeNativeIconAction(
        controlKey: widget.controlKey,
        focusNode: _focus,
        autofocus: widget.autofocus,
        constraints: widget.constraints,
        padding: widget.padding,
        style: quietStyle,
        selected: widget.selected,
        onActivate: enabled ? _activate : null,
        label: widget.label,
        consumeHintEscape: widget.consumeHintEscape,
        icon: widget.icon,
      );
    } else {
      control = ConstrainedBox(
        constraints:
            widget.constraints ??
            const BoxConstraints(minWidth: 40, minHeight: 40),
        child: SuitePressable(
          key: widget.controlKey,
          kind: widget.quiet ? PressableKind.row : PressableKind.icon,
          baseRadius:
              Theme.of(context)
                  .extension<StarBridgeTokens>()
                  ?.shape
                  .radiusSmall ??
              6,
          minHeight: 40,
          padding: widget.padding ?? const EdgeInsets.all(8),
          selected: widget.selected ?? false,
          focusNode: _focus,
          autofocus: widget.autofocus,
          onActivate: enabled ? _activate : null,
          child: Center(widthFactor: 1, heightFactor: 1, child: widget.icon),
        ),
      );
    }
    return StarBridgeTooltip(
      message: widget.label,
      consumeEscape: widget.consumeHintEscape,
      excludeFromSemantics: true,
      child: ListenableBuilder(
        listenable: _focus,
        child: enabled
            ? control
            : IgnorePointer(child: ExcludeFocus(child: control)),
        builder: (context, child) => Semantics(
          container: true,
          button: true,
          toggled: widget.selected,
          enabled: enabled,
          focusable: enabled,
          focused: enabled ? _focus.hasFocus : null,
          label: widget.label,
          // Read-screen activation takes the instant, non-decorative path.
          onTap: enabled ? () => _activate(InteractionSource.keyboard) : null,
          excludeSemantics: true,
          child: child,
        ),
      ),
    );
  }
}
