import 'package:flutter/material.dart';

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
      color: framed ? BridgeInk.panel : Colors.transparent,
      border: framed
          ? const Border(
              top: BorderSide(color: BridgeInk.blue, width: .8),
              bottom: BorderSide(color: BridgeInk.line, width: .6),
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
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });
  final String label;
  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;
  final EdgeInsetsGeometry padding;
  @override
  State<BridgeMenuAction> createState() => _BridgeMenuActionState();
}

class _BridgeMenuActionState extends State<BridgeMenuAction> {
  bool hovered = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final highlighted = hovered || focused || widget.selected;
    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      selected: widget.selected,
      label: widget.label,
      onTap: widget.onPressed,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        mouseCursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => hovered = value),
        onShowFocusHighlight: (value) => setState(() => focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: ExcludeSemantics(
            child: Container(
              padding: widget.padding,
              decoration: BoxDecoration(
                color: hovered || focused
                    ? BridgeInk.selected.withValues(alpha: .22)
                    : Colors.transparent,
                border: Border(
                  top: BorderSide(
                    color: highlighted ? BridgeInk.blue : Colors.transparent,
                  ),
                  bottom: BorderSide(
                    color: focused ? BridgeInk.blue : Colors.transparent,
                  ),
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class BridgeCaption extends StatelessWidget {
  const BridgeCaption(this.text, {super.key, this.color = BridgeInk.muted});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 13, color: color, height: 1.5));
}

class BridgeBadge extends StatelessWidget {
  const BridgeBadge(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: BridgeInk.selected,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      value,
      style: const TextStyle(
        color: BridgeInk.blue,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
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
