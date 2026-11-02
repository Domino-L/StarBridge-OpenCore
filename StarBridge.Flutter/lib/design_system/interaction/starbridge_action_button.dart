import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../tokens/starbridge_tokens.dart';
import '../controls/semantic_action_style.dart';
import 'starbridge_interaction_theme.dart';
import 'starbridge_activation_origin.dart';
import 'starbridge_native_ink.dart';

enum StarBridgeActionKind { primary, secondary, quiet, danger }

/// Keeps standard Material sizing and exposes the approved suite feedback
/// only when the settings owner selects a suite. Commands are never delayed
/// or coalesced by this presentation layer.
class StarBridgeActionButton extends StatefulWidget {
  const StarBridgeActionButton({
    required this.child,
    this.onActivate,
    this.kind = StarBridgeActionKind.secondary,
    this.tone,
    this.controlKey,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.nativeStyle,
    this.padding,
    this.minHeight,
    this.hoverFace = true,
    super.key,
  });

  final Widget child;
  final ValueChanged<InteractionSource>? onActivate;
  final StarBridgeActionKind kind;

  /// Preserve existing warning/success/info/danger meaning in every suite.
  /// Does not change the command, confirmation or save-state owner.
  final ActionTone? tone;
  final Key? controlKey;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  /// Optional existing control geometry/appearance; default recipes unchanged.
  final ButtonStyle? nativeStyle;
  final EdgeInsetsGeometry? padding;
  final double? minHeight;

  /// False inside a surface that draws its own hover (MarketHoverCard): no
  /// second suite hover face; press and focus feedback stay.
  final bool hoverFace;

  @override
  State<StarBridgeActionButton> createState() => _StarBridgeActionButtonState();
}

class _StarBridgeActionButtonState extends State<StarBridgeActionButton> {
  InteractionSource _nativeSource = InteractionSource.keyboard;
  final _ink = StarBridgeNativeInk();
  final _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;

  @override
  void dispose() {
    _ink.dispose();
    _ownedFocus.dispose();
    super.dispose();
  }

  void _activate(InteractionSource source) {
    _nativeSource = InteractionSource.keyboard;
    if (source != InteractionSource.pointer) _ink.retire();
    unawaited(
      runStarBridgeActivation<void>(
        source,
        () => widget.onActivate?.call(source),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: ListenableBuilder(
      listenable: _focus,
      builder: (context, _) => _buildControl(context),
    ),
  );

  Widget _buildControl(BuildContext context) {
    final data = InteractionScope.of(context);
    final theme = Theme.of(context);
    final tokens = theme.extension<StarBridgeTokens>();
    if (data.suite != InteractionSuite.standard) {
      _ink.retire();
      // A caller's native secondary fill is an existing state cue (for
      // example a selected filter), not a decoration behind an opaque suite
      // face. Resolve the current disabled/enabled state and paint it once.
      final nativeFill = widget.kind == StarBridgeActionKind.secondary
          ? widget.nativeStyle?.backgroundColor?.resolve({
              if (widget.onActivate == null) WidgetState.disabled,
            })
          : null;
      final nativeForeground = widget.nativeStyle?.foregroundColor?.resolve({
        if (widget.onActivate == null) WidgetState.disabled,
      });
      final control = SuitePressable(
        key: widget.controlKey,
        hoverFace: widget.hoverFace,
        kind: switch (widget.kind) {
          StarBridgeActionKind.primary => PressableKind.primary,
          StarBridgeActionKind.secondary => PressableKind.secondary,
          StarBridgeActionKind.quiet => PressableKind.row,
          StarBridgeActionKind.danger => PressableKind.danger,
        },
        onActivate: widget.onActivate == null ? null : _activate,
        semanticLabel: widget.semanticLabel,
        semanticFocused: widget.onActivate != null ? _focus.hasFocus : null,
        excludeChildSemantics: widget.semanticLabel != null,
        focusNode: _focus,
        autofocus: widget.autofocus,
        baseRadius: tokens?.shape.radiusSmall ?? 6,
        // Match the approved lab's basic button: 34 high, 14 x 8 padding.
        // Keep the client's density factor rather than pinning physical pixels.
        minHeight:
            widget.minHeight ??
            (tokens?.density.controlHeight ?? 40) * (34 / 40),
        padding:
            widget.padding ??
            widget.nativeStyle?.padding?.resolve({}) ??
            EdgeInsets.symmetric(
              horizontal: tokens?.space.md ?? 14,
              vertical: (tokens?.density.controlHeight ?? 40) * (8 / 40),
            ),
        builder: (context, visual) => DefaultTextStyle.merge(
          style: theme.textTheme.labelLarge?.copyWith(color: visual.foreground),
          // Material buttons center their content after applying minHeight.
          // SuitePressable deliberately leaves layout to the caller (rows and
          // cards need different alignment). Do not stretch Text to the full
          // button height: its glyphs would remain painted at the top.
          child: Align(widthFactor: 1, heightFactor: 1, child: widget.child),
        ),
      );
      // Preserve labels while removing all pointer/semantics activation and
      // keyboard focus from disabled suite controls at the client boundary.
      Widget target = widget.onActivate == null
          ? IgnorePointer(child: ExcludeFocus(child: control))
          : control;
      // Keep this target's implicit label with its role, without merging a
      // sibling heading into the button's accessible name.
      target = MergeSemantics(
        child: Semantics(
          container: true,
          focusable: widget.onActivate != null,
          child: target,
        ),
      );
      if (widget.nativeStyle case final style?) {
        final minimum = style.minimumSize?.resolve({});
        final maximum = style.maximumSize?.resolve({});
        target = ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minimum?.width ?? 0,
            minHeight: minimum?.height ?? 0,
            maxWidth: maximum?.width ?? double.infinity,
            maxHeight: maximum?.height ?? double.infinity,
          ),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: nativeFill == null
                  ? style.backgroundColor?.resolve({})
                  : null,
              shape: style.shape?.resolve({}) ?? const RoundedRectangleBorder(),
            ),
            child: target,
          ),
        );
      }
      final tone = widget.tone;
      if ((tone == null || tokens == null) && widget.nativeStyle == null) {
        return target;
      }
      // Keep the scope present for the lifetime of a supplied native style,
      // including a null resolved fill. Selection must not replace its face
      // (and owned focus node) merely because the fill becomes non-null.
      final color = switch (tone) {
        ActionTone.danger => tokens?.colors.danger,
        ActionTone.warning => tokens?.colors.warning,
        ActionTone.success => tokens?.colors.success,
        ActionTone.info => tokens?.colors.info,
        null => null,
      };
      final p = data.palette;
      return InteractionScope(
        data: data.copyWith(
          palette: InteractionPalette(
            brightness: p.brightness,
            accent: color ?? p.accent,
            accentBright: color ?? p.accentBright,
            onAccent: p.onAccent,
            selectedFill: p.selectedFill,
            surface: p.surface,
            raised: nativeFill ?? p.raised,
            border: widget.onActivate == null ? p.border : color ?? p.border,
            textPrimary: color ?? nativeForeground ?? p.textPrimary,
            textSecondary: color ?? nativeForeground ?? p.textSecondary,
            textDisabled: widget.onActivate == null
                ? nativeForeground ?? p.textDisabled
                : p.textDisabled,
            focusRing: color ?? p.focusRing,
            success: p.success,
            onSuccess: p.onSuccess,
            danger: color ?? p.danger,
            onDanger: p.onDanger,
            warning: p.warning,
          ),
        ),
        child: target,
      );
    }
    final enabled = widget.onActivate != null;
    final VoidCallback? callback = enabled
        ? () => _activate(_nativeSource)
        : null;
    final toneStyle = widget.tone == null
        ? widget.nativeStyle
        : (widget.nativeStyle ?? const ButtonStyle()).merge(
            semanticActionStyle(
              context,
              widget.tone!,
              emphasis: switch (widget.kind) {
                StarBridgeActionKind.primary ||
                StarBridgeActionKind.danger => ActionEmphasis.filled,
                StarBridgeActionKind.secondary => ActionEmphasis.outlined,
                StarBridgeActionKind.quiet => ActionEmphasis.text,
              },
            ),
          );
    final baseStyle =
        widget.kind == StarBridgeActionKind.danger && widget.tone == null
        ? (toneStyle ?? const ButtonStyle()).copyWith(
            backgroundColor: WidgetStatePropertyAll(data.palette.danger),
            foregroundColor: WidgetStatePropertyAll(data.palette.onDanger),
          )
        : toneStyle ?? const ButtonStyle();
    final buttonStyle = _ink.resolveStyle(
      context,
      animated: !data.reduceMotion,
      style: baseStyle,
      themeStyle: switch (widget.kind) {
        StarBridgeActionKind.primary ||
        StarBridgeActionKind.danger => FilledButtonTheme.of(context).style,
        StarBridgeActionKind.secondary => OutlinedButtonTheme.of(context).style,
        StarBridgeActionKind.quiet => TextButtonTheme.of(context).style,
      },
    );
    final Widget button = switch (widget.kind) {
      StarBridgeActionKind.primary ||
      StarBridgeActionKind.danger => FilledButton(
        key: widget.controlKey,
        focusNode: _focus,
        statesController: _ink.states,
        autofocus: widget.autofocus,
        onPressed: callback,
        style: buttonStyle,
        child: widget.child,
      ),
      StarBridgeActionKind.secondary => OutlinedButton(
        key: widget.controlKey,
        focusNode: _focus,
        statesController: _ink.states,
        autofocus: widget.autofocus,
        onPressed: callback,
        style: buttonStyle,
        child: widget.child,
      ),
      StarBridgeActionKind.quiet => TextButton(
        key: widget.controlKey,
        focusNode: _focus,
        statesController: _ink.states,
        autofocus: widget.autofocus,
        onPressed: callback,
        style: buttonStyle,
        child: widget.child,
      ),
    };
    return CallbackShortcuts(
      bindings: {
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.numpadEnter,
          LogicalKeyboardKey.space,
        ])
          SingleActivator(key): () {
            if (enabled) _activate(InteractionSource.keyboard);
          },
      },
      child: Listener(
        onPointerDown: (_) => _nativeSource = InteractionSource.pointer,
        onPointerCancel: (_) => _nativeSource = InteractionSource.keyboard,
        child: MergeSemantics(
          child: Semantics(
            container: true,
            button: true,
            enabled: enabled,
            focusable: enabled,
            focused: enabled ? _focus.hasFocus : null,
            label: widget.semanticLabel,
            // Keep implicit labels, but suppress descendant tap actions: the
            // Material action would otherwise synthesize a pointer splash.
            excludeSemantics: widget.semanticLabel != null,
            onTap: enabled ? () => _activate(InteractionSource.keyboard) : null,
            child: Semantics(blockUserActions: true, child: button),
          ),
        ),
      ),
    );
  }
}
