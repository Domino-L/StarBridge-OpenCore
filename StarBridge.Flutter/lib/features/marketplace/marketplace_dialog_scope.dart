import 'package:flutter/widgets.dart';

/// Marks a hall hosted inside a panel. Its dialogs then belong to the nearest
/// navigator, so they stay in the panel and leave with it. In the client there
/// is no scope and they keep covering the whole window.
class MarketplaceDialogScope extends InheritedWidget {
  const MarketplaceDialogScope({super.key, required super.child});

  static bool useRootNavigator(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MarketplaceDialogScope>() == null;

  @override
  bool updateShouldNotify(MarketplaceDialogScope oldWidget) => false;
}
