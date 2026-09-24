import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared desktop chat behavior. IME confirmation must remain an input event.
class ChatSendShortcuts extends StatelessWidget {
  const ChatSendShortcuts({
    required this.controller,
    required this.onSend,
    required this.child,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback? onSend;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event.logicalKey != LogicalKeyboardKey.enter &&
          event.logicalKey != LogicalKeyboardKey.numpadEnter) {
        return KeyEventResult.ignored;
      }
      final keyboard = HardwareKeyboard.instance;
      final composing = controller.value.composing;
      if (keyboard.isShiftPressed ||
          keyboard.isAltPressed ||
          keyboard.isMetaPressed ||
          (composing.isValid && !composing.isCollapsed)) {
        return KeyEventResult.ignored;
      }
      // Keep Ctrl+Enter compatible; neither a held key nor a blocked send
      // should insert newlines or submit the same message again.
      if (event is KeyDownEvent) onSend?.call();
      return KeyEventResult.handled;
    },
    child: child,
  );
}
