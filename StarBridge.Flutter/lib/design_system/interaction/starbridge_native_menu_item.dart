import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_native_ink.dart';

/// Native menu geometry and focus, with owned ink that can stop immediately.
/// The caller still owns availability, selection, close policy and commands.
class StarBridgeNativeMenuItem extends StatefulWidget {
  const StarBridgeNativeMenuItem({
    required this.controlKey,
    required this.focusNode,
    required this.label,
    required this.child,
    required this.animated,
    this.selected,
    this.onActivate,
    super.key,
  });

  final Key controlKey;
  final FocusNode focusNode;
  final String label;
  final Widget child;
  final bool animated;
  final bool? selected;
  final ValueChanged<InteractionSource>? onActivate;

  @override
  State<StarBridgeNativeMenuItem> createState() => _NativeMenuItemState();
}

class _NativeMenuItemState extends State<StarBridgeNativeMenuItem> {
  final _ink = StarBridgeNativeInk();

  void _activate(InteractionSource source) {
    if (source != InteractionSource.pointer) _ink.retire();
    widget.onActivate?.call(source);
  }

  @override
  void dispose() {
    _ink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const native = MenuItemButton(child: SizedBox.shrink());
    final style = (native.themeStyleOf(context) ?? const ButtonStyle()).merge(
      native.defaultStyleOf(context),
    );
    final resolved = _ink.resolveStyle(
      context,
      animated: widget.animated,
      style: style,
      themeStyle: null,
    );
    final enabled = widget.onActivate != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      onTap: enabled ? () => _activate(InteractionSource.keyboard) : null,
      child: CallbackShortcuts(
        bindings: {
          for (final key in [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.space,
            LogicalKeyboardKey.numpadEnter,
          ])
            SingleActivator(key): () => _activate(InteractionSource.keyboard),
        },
        child: LayoutBuilder(
          builder: (context, constraints) => MenuItemButton(
            key: widget.controlKey,
            focusNode: widget.focusNode,
            closeOnActivate: false,
            statesController: _ink.states,
            style: resolved,
            onPressed: enabled
                ? () => _activate(InteractionSource.pointer)
                : null,
            child: SizedBox(
              width: (constraints.maxWidth - 24).clamp(0, double.infinity),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
