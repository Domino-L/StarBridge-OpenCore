import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Menu engine side of "open this client page". The method names one fixed
/// page; native hides the menu and raises the client only after the primary
/// engine accepts it. No route or payload ever leaves this engine.
final class MenuToolPageOpener {
  const MenuToolPageOpener(this.channel, this.opening);
  final MethodChannel channel;

  /// Current menu opening, or null while the menu is not wanted.
  final int? Function() opening;

  Future<bool> openHudSettings() async {
    final current = opening();
    if (current == null || current <= 0) return false;
    try {
      final opened = await channel
          .invokeMethod<bool>('openHudSettings', {'opening': current})
          .timeout(const Duration(seconds: 6));
      return opened == true;
    } on Object {
      return false;
    }
  }
}

/// Lets menu panels reach the opener without threading it through the
/// workspace. Absent in previews and tests that do not provide it.
class MenuToolPageScope extends InheritedWidget {
  const MenuToolPageScope({
    super.key,
    required this.opener,
    required super.child,
  });
  final MenuToolPageOpener? opener;

  static MenuToolPageOpener? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MenuToolPageScope>()?.opener;

  @override
  bool updateShouldNotify(MenuToolPageScope oldWidget) =>
      (opener == null) != (oldWidget.opener == null);
}
