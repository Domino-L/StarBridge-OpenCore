import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../tokens/starbridge_tokens.dart';
import 'starbridge_interaction_theme.dart';

/// A presentation-only navigation target. Pointer activation keeps feedback
/// even when the destination is already selected. Reader/key activation uses
/// the instant command; the owner still decides whether navigation succeeds.
class StarBridgeNavigationTarget extends StatefulWidget {
  const StarBridgeNavigationTarget({
    required this.child,
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.onKeyboardPressed,
    required this.onPrevious,
    required this.onNext,
    this.focusNode,
    this.sharedSelection = false,
    this.selectionStripe,
    this.brand = false,
    super.key,
  });
  final Widget child;
  final String label;
  final bool selected;
  final VoidCallback onPressed, onKeyboardPressed, onPrevious, onNext;
  final FocusNode? focusNode;
  final bool sharedSelection, brand;
  final Widget? selectionStripe;

  @override
  State<StarBridgeNavigationTarget> createState() =>
      _StarBridgeNavigationTargetState();
}

class _StarBridgeNavigationTargetState
    extends State<StarBridgeNavigationTarget> {
  late final _localFocus = FocusNode(debugLabel: 'navigation-target');
  FocusNode get _focus => widget.focusNode ?? _localFocus;

  @override
  void dispose() {
    _localFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        final tokens = context.tokens;
        final native = data.suite == InteractionSuite.standard;
        final chrome =
            widget.selected &&
            !widget.brand &&
            (native || !widget.sharedSelection);
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowUp):
                widget.onPrevious,
            const SingleActivator(LogicalKeyboardKey.arrowDown): widget.onNext,
          },
          child: AnimatedBuilder(
            animation: _focus,
            builder: (context, child) => Material(
              color: chrome
                  ? tokens.surfaces.selected.fill
                  : native || widget.brand
                  ? tokens.surfaces.navigation.fill
                  : Colors.transparent,
              borderRadius: widget.brand
                  ? BorderRadius.zero
                  : tokens.shape.small,
              child: SuitePressable(
                kind: PressableKind.navItem,
                baseRadius: widget.brand ? 0 : tokens.shape.radiusSmall,
                focusNode: _focus,
                semanticSelected: widget.selected,
                semanticFocused: _focus.hasFocus,
                semanticLabel: widget.label,
                excludeChildSemantics: true,
                onActivate: (source) => source == InteractionSource.keyboard
                    ? widget.onKeyboardPressed()
                    : widget.onPressed(),
                child: Stack(
                  children: [
                    widget.child,
                    if (chrome && widget.selectionStripe != null)
                      widget.selectionStripe!,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
