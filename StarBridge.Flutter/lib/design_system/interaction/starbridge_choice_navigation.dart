import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_tracked_navigation.dart';
import 'starbridge_tooltip.dart';

@immutable
class StarBridgeNavigationChoice {
  const StarBridgeNavigationChoice({
    required this.id,
    required this.label,
    required this.child,
    this.enabled = true,
    this.hint = '',
    this.controlKey,
  });
  final String id, label, hint;
  final Widget child;
  final bool enabled;
  final Key? controlKey;
}

/// A face of the host's own that replaces the chip for one choice.
typedef StarBridgeChoiceFaceBuilder = Widget Function(
  BuildContext context,
  StarBridgeNavigationChoice choice,
  bool selected,
  FocusNode focusNode,
  ValueChanged<InteractionSource> activate,
);

/// Intrinsic-width choice navigation. The host retains capability, async leave
/// guards and confirmed selected id. Original ChoiceChip geometry/chrome stays
/// intact for standard; custom suites share the approved tab painter, not data.
class StarBridgeChoiceNavigation extends StatelessWidget {
  const StarBridgeChoiceNavigation({
    required this.choices,
    required this.selected,
    required this.onSelected,
    this.changeSource,
    this.faceBuilder,
    super.key,
  });
  final List<StarBridgeNavigationChoice> choices;
  final String selected;
  final ValueChanged<String> onSelected;
  final InteractionSource? changeSource;

  /// Organization pages' holo tabs draw their own face and follow no suite, so
  /// no suite indicator frames them (user decisions 2026-10-29, 2026-10-30).
  /// Selection, focus order and arrow keys stay with the track.
  final StarBridgeChoiceFaceBuilder? faceBuilder;

  @override
  Widget build(BuildContext context) => StarBridgeTrackedNavigation(
    items: [
      for (final item in choices)
        TrackItem(id: item.id, label: item.label, enabled: item.enabled),
    ],
    selected: selected,
    onSelected: onSelected,
    changeSource: changeSource,
    spacing: 8,
    plainTrack: faceBuilder != null,
    targetBuilder: (context, item, selected, focus, activate) {
      final choice = choices.firstWhere((choice) => choice.id == item.id);
      final face = faceBuilder;
      return face == null
          ? _ChoiceTarget(
              choice: choice,
              selected: selected,
              focusNode: focus,
              activate: activate,
            )
          : _withHint(choice, face(context, choice, selected, focus, activate));
    },
  );
}

// Passive hints do not consume the owning page/menu's Escape. Empty hints
// still introduce no extra tooltip/reader node.
Widget _withHint(StarBridgeNavigationChoice choice, Widget target) =>
    choice.hint.isEmpty
    ? target
    : StarBridgeTooltip(
        message: choice.hint,
        consumeEscape: false,
        child: target,
      );

class _ChoiceTarget extends StatefulWidget {
  const _ChoiceTarget({
    required this.choice,
    required this.selected,
    required this.focusNode,
    required this.activate,
  });
  final StarBridgeNavigationChoice choice;
  final bool selected;
  final FocusNode focusNode;
  final ValueChanged<InteractionSource> activate;
  @override
  State<_ChoiceTarget> createState() => _ChoiceTargetState();
}

class _ChoiceTargetState extends State<_ChoiceTarget> {
  InteractionSource _nativeSource = InteractionSource.keyboard;
  void _activate(InteractionSource source) {
    _nativeSource = InteractionSource.keyboard;
    if (widget.choice.enabled) widget.activate(source);
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final native = data.suite == InteractionSuite.standard;
    final choice = widget.choice;
    final chip = ChoiceChip(
      key: native ? choice.controlKey : null,
      label: choice.child,
      showCheckmark: false,
      labelStyle: Theme.of(context).textTheme.labelLarge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      elevation: 0,
      pressElevation: 0,
      chipAnimationStyle: ChipAnimationStyle(
        enableAnimation: AnimationStyle.noAnimation,
        selectAnimation: AnimationStyle.noAnimation,
        avatarDrawerAnimation: AnimationStyle.noAnimation,
        deleteDrawerAnimation: AnimationStyle.noAnimation,
      ),
      selected: widget.selected,
      color: native ? null : const WidgetStatePropertyAll(Colors.transparent),
      side: native ? null : const BorderSide(color: Colors.transparent),
      focusNode: native ? widget.focusNode : null,
      onSelected: choice.enabled ? (_) => _activate(_nativeSource) : null,
    );
    Widget target;
    if (native) {
      target = CallbackShortcuts(
        bindings: {
          if (choice.enabled)
            for (final key in [
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.numpadEnter,
              LogicalKeyboardKey.space,
            ])
              SingleActivator(key): () => _activate(InteractionSource.keyboard),
        },
        child: AnimatedBuilder(
          animation: widget.focusNode,
          builder: (context, _) => Semantics(
            button: true,
            enabled: choice.enabled,
            selected: widget.selected,
            focusable: choice.enabled,
            focused: widget.focusNode.hasFocus,
            inMutuallyExclusiveGroup: true,
            label: choice.label,
            excludeSemantics: true,
            onTap: choice.enabled
                ? () => _activate(InteractionSource.keyboard)
                : null,
            child: Listener(
              onPointerDown: (_) => _nativeSource = InteractionSource.pointer,
              child: chip,
            ),
          ),
        ),
      );
    } else {
      target = AnimatedBuilder(
        animation: widget.focusNode,
        builder: (context, _) => SuitePressable(
          key: choice.controlKey,
          kind: PressableKind.tab,
          baseRadius: 6,
          semanticSelected: widget.selected,
          semanticFocused: widget.focusNode.hasFocus,
          semanticLabel: choice.label,
          excludeChildSemantics: true,
          focusNode: widget.focusNode,
          onActivate: choice.enabled ? _activate : null,
          child: IgnorePointer(child: ExcludeFocus(child: chip)),
        ),
      );
      if (!choice.enabled) {
        target = IgnorePointer(child: ExcludeFocus(child: target));
      }
    }
    return _withHint(choice, target);
  }
}
