import 'package:flutter/widgets.dart';

/// Marks a client page hosted inside a panel (the game menu). Its dialogs then
/// open on the nearest navigator, so they stay in the panel and leave with it.
/// The client has no scope: dialogs keep covering the whole window there.
class PanelDialogScope extends InheritedWidget {
  const PanelDialogScope({super.key, required super.child});

  /// Whether a dialog that asks for the root navigator may have it.
  static bool allowsRoot(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PanelDialogScope>() == null;

  @override
  bool updateShouldNotify(PanelDialogScope oldWidget) => false;
}
