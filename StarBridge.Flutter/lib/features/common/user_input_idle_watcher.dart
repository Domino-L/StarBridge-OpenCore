import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Reports when nobody has touched the client for a while, so reads that only
/// serve someone looking at the screen can stop. Any pointer or key resumes.
final class UserInputIdleWatcher {
  UserInputIdleWatcher({required this.onChanged, this.idleAfter = defaultIdle}) {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _arm();
  }

  static const defaultIdle = Duration(minutes: 2);

  final Duration idleAfter;
  final void Function() onChanged;
  Timer? _idle;
  bool _active = true, _closed = false;
  bool get active => _active;

  void _onPointer(PointerEvent event) => _note();

  bool _onKey(KeyEvent event) {
    _note();
    return false;
  }

  void _arm() {
    _idle?.cancel();
    _idle = Timer(idleAfter, () {
      if (_closed) return;
      _active = false;
      onChanged();
    });
  }

  void _note() {
    if (_closed) return;
    _arm();
    if (!_active) {
      _active = true;
      onChanged();
    }
  }

  void dispose() {
    _closed = true;
    _idle?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
  }
}
