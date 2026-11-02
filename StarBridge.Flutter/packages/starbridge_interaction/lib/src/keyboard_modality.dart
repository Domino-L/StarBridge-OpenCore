import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether focus visuals belong on screen: the user is driving the UI with
/// the keyboard. Set by any key press, cleared by any pointer press; before
/// any pointer press (a fresh start, an autofocused dialog) focus shows as
/// native controls show it.
///
/// Desktop [FocusHighlightMode] stays "traditional" for mouse users too, so
/// it cannot tell keyboard focus from a menu or dialog handing focus back to
/// its anchor after a click. Relying on it left the account button framed as
/// focused after its menu closed, long after the pointer had moved on
/// (build 11 report). An explicit [FocusHighlightStrategy.alwaysTraditional]
/// still always shows focus.
abstract final class KeyboardModality {
  static final ValueNotifier<bool> _active = ValueNotifier(true);
  static int _users = 0;

  /// Changes whenever the input modality flips.
  static ValueListenable<bool> get listenable => _active;

  static bool get showsFocus =>
      _active.value ||
      FocusManager.instance.highlightStrategy ==
          FocusHighlightStrategy.alwaysTraditional;

  /// Installs the shared input listeners with the first user; [release]
  /// removes them with the last, so nothing stays registered without users.
  static void retain() {
    if (_users++ > 0) return;
    _active.value = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    HardwareKeyboard.instance.addHandler(_key);
  }

  static void release() {
    if (--_users > 0) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    HardwareKeyboard.instance.removeHandler(_key);
  }

  static void _pointer(PointerEvent event) {
    if (event is PointerDownEvent) _active.value = false;
  }

  static bool _key(KeyEvent event) {
    if (event is KeyDownEvent) _active.value = true;
    return false;
  }
}
