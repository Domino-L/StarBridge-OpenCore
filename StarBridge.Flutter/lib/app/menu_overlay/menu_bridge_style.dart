import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

import '../shell/widgets/attention_badge.dart';

import '../../design_system/icons/menu_bridge_glyph.dart';
import '../../design_system/styles/menu_bridge_palette.dart';
export '../../design_system/icons/menu_bridge_glyph.dart';
export '../../design_system/styles/menu_bridge_palette.dart';

class BridgePlate extends StatelessWidget {
  const BridgePlate({
    super.key,
    required this.child,
    this.framed = true,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final bool framed;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: framed ? MenuBridgeColors.of(context).panel : Colors.transparent,
      border: framed
          ? Border(
              top: BorderSide(
                color: MenuBridgeColors.of(context).blue,
                width: .8,
              ),
              bottom: BorderSide(
                color: MenuBridgeColors.of(context).line,
                width: .6,
              ),
            )
          : null,
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// Menu-only desktop control: explicit focus/hover, no Material ink or pill.
class BridgeMenuAction extends StatefulWidget {
  const BridgeMenuAction({
    super.key,
    required this.label,
    required this.child,
    this.onPressed,
    this.focusNode,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });
  final String label;
  final Widget child;
  final VoidCallback? onPressed;

  /// A popup can own its actual trigger focus, including visible return.
  /// Null retains the original locally-owned focus lifecycle.
  final FocusNode? focusNode;
  final bool selected;
  final EdgeInsetsGeometry padding;
  @override
  State<BridgeMenuAction> createState() => _BridgeMenuActionState();
}

class _BridgeMenuActionState extends State<BridgeMenuAction> {
  bool hovered = false, focused = false;
  final _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;

  void _activate(InteractionSource source) =>
      runStarBridgeSynchronousActivation(
        source,
        () => widget.onPressed?.call(),
      );

  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StarBridgeInteractionRegion(child: Builder(builder: _face));

  Widget _face(BuildContext context) {
    final ink = MenuBridgeColors.of(context);
    final data = InteractionScope.of(context);
    if (data.suite != InteractionSuite.standard) {
      final action = SuitePressable(
        kind: PressableKind.row,
        focusNode: _focus,
        selected: widget.selected,
        semanticLabel: widget.label,
        semanticSelected: widget.selected,
        excludeChildSemantics: true,
        baseRadius: 0,
        onActivate: widget.onPressed == null ? null : _activate,
        builder: (context, visual) => Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: visual.hover > 0 || visual.focused
                ? ink.selected.withValues(alpha: .22)
                : Colors.transparent,
            border: Border(
              top: BorderSide(
                color: visual.hover > 0 || visual.focused || widget.selected
                    ? ink.blue
                    : Colors.transparent,
              ),
              bottom: BorderSide(
                color: visual.focused ? ink.blue : Colors.transparent,
              ),
            ),
          ),
          child: widget.child,
        ),
      );
      return widget.onPressed == null
          ? IgnorePointer(child: ExcludeFocus(child: action))
          : action;
    }
    final highlighted = hovered || focused || widget.selected;
    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      selected: widget.selected,
      label: widget.label,
      onTap: widget.onPressed == null
          ? null
          : () => _activate(InteractionSource.keyboard),
      child: CallbackShortcuts(
        bindings: {
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.numpadEnter,
            LogicalKeyboardKey.space,
          ])
            SingleActivator(key): () {
              if (widget.onPressed != null) {
                _activate(InteractionSource.keyboard);
              }
            },
        },
        child: FocusableActionDetector(
          focusNode: _focus,
          enabled: widget.onPressed != null,
          mouseCursor: widget.onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onShowHoverHighlight: (value) => setState(() => hovered = value),
          onShowFocusHighlight: (value) => setState(() => focused = value),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activate(InteractionSource.keyboard);
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed == null
                ? null
                : () => _activate(InteractionSource.pointer),
            child: ExcludeSemantics(
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: hovered || focused
                      ? ink.selected.withValues(alpha: .22)
                      : Colors.transparent,
                  border: Border(
                    top: BorderSide(
                      color: highlighted ? ink.blue : Colors.transparent,
                    ),
                    bottom: BorderSide(
                      color: focused ? ink.blue : Colors.transparent,
                    ),
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BridgeCaption extends StatelessWidget {
  const BridgeCaption(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      color: color ?? MenuBridgeColors.of(context).muted,
      height: 1.5,
    ),
  );
}

class BridgeBadge extends StatelessWidget {
  const BridgeBadge(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) =>
      AttentionCount(count: int.tryParse(value) ?? 0);
}

class BridgeLabel extends StatelessWidget {
  const BridgeLabel(this.icon, this.label, {super.key});
  final MenuGlyph icon;
  final String label;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      MenuGlyphView(icon, size: 18, color: BridgeInk.muted),
      Text(label),
    ],
  );
}

class BridgeAvatar extends StatelessWidget {
  const BridgeAvatar(this.letter, {super.key, this.online = true});
  final String letter;
  final bool online;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 40,
    child: Stack(
      children: [
        Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BridgeInk.selected,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(letter, style: const TextStyle(fontSize: 18)),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? BridgeInk.green : BridgeInk.blue,
              border: Border.all(color: BridgeInk.ground, width: 2),
            ),
          ),
        ),
      ],
    ),
  );
}
