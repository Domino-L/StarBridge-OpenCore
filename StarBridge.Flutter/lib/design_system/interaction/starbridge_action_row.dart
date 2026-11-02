import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../tokens/starbridge_tokens.dart';
import 'starbridge_activation_origin.dart';
import 'starbridge_interaction_theme.dart';

/// Presentation-only target for existing rows. The callback receives a context
/// below the live scope, so legacy route openers keep both settings and origin.
class StarBridgeActionRow extends StatefulWidget {
  const StarBridgeActionRow({
    required this.child,
    this.onActivate,
    this.controlKey,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.semanticSelected,
    this.baseRadius,
    this.inheritContentStyle = false,
    this.hoverFace = true,
    super.key,
  });

  final Widget child;
  final void Function(BuildContext context, InteractionSource source)?
  onActivate;
  final Key? controlKey;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final bool? semanticSelected;
  final double? baseRadius;

  /// Keep the row content's own text and icon style. The pressable otherwise
  /// tints content with its row foreground and, in the standard suite, its
  /// ink Material resets text to bodyMedium. Existing data rows migrating from
  /// a bare InkWell (which changes neither) opt in to keep their look.
  final bool inheritContentStyle;

  /// False inside a surface that draws its own hover (MarketHoverCard): no
  /// second suite hover face; press and focus feedback stay.
  final bool hoverFace;

  @override
  State<StarBridgeActionRow> createState() => _StarBridgeActionRowState();
}

class _StarBridgeActionRowState extends State<StarBridgeActionRow> {
  final _source = ValueNotifier(InteractionSource.pointer);

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: StarBridgeActivationOrigin(
      source: _source,
      child: Builder(builder: _buildTarget),
    ),
  );

  Widget _buildTarget(BuildContext context) {
    final control = SuitePressable(
      key: widget.controlKey,
      kind: PressableKind.row,
      hoverFace: widget.hoverFace,
      baseRadius:
          widget.baseRadius ??
          Theme.of(context).extension<StarBridgeTokens>()?.shape.radiusSmall ??
          6,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      semanticLabel: widget.semanticLabel,
      semanticSelected: widget.semanticSelected,
      onActivate: widget.onActivate == null
          ? null
          : (source) {
              _source.value = source;
              unawaited(
                runStarBridgeActivation<void>(
                  source,
                  () => widget.onActivate!(context, source),
                ),
              );
            },
      child: widget.inheritContentStyle
          ? _inherited(context, widget.child)
          : widget.child,
    );
    return widget.onActivate == null
        ? IgnorePointer(child: ExcludeFocus(child: control))
        : control;
  }
}

/// The content's surrounding text/icon style, re-applied inside the target.
Widget _inherited(BuildContext context, Widget child) {
  final text = DefaultTextStyle.of(context);
  return DefaultTextStyle(
    style: text.style,
    textAlign: text.textAlign,
    softWrap: text.softWrap,
    overflow: text.overflow,
    maxLines: text.maxLines,
    textWidthBasis: text.textWidthBasis,
    textHeightBehavior: text.textHeightBehavior,
    child: IconTheme(data: IconTheme.of(context), child: child),
  );
}
