import 'package:flutter/widgets.dart';

/// An explicit exit still passes through the runtime's close/unsaved guards.
class ExitApplicationIntent extends Intent {
  const ExitApplicationIntent({this.beforeExit});

  /// Prepare a confirmed update only after all unsaved/leave guards pass.
  /// A failed helper handoff must keep the current client running.
  final Future<bool> Function()? beforeExit;
}
