final class MenuHotkeyIntent {
  const MenuHotkeyIntent(
    this.action,
    this.request,
    this.targetWindow,
    this.targetProcessId,
  );
  final String action;
  final int request, targetWindow, targetProcessId;
}

typedef MenuOpenLabels = ({
  String contextLabel,
  String returnLabel,
  String settingsLabel,
});

abstract interface class MenuHotkeyPort {
  void initialize(
    int Function() nextClient,
    Future<void> Function(MenuHotkeyIntent) onIntent,
    void Function() onRevoked,
  );
  Future<void> window(int request, String phase, int handle);
  void dispose();
}
