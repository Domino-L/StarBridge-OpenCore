import 'package:flutter/foundation.dart';

final class RuntimeInstallationFacts {
  const RuntimeInstallationFacts({
    required this.dataDirectory,
    required this.imageCacheDirectory,
    required this.imageCacheExists,
    this.applicationVersion,
    this.serverOrigin,
  });
  final String dataDirectory, imageCacheDirectory;
  final bool imageCacheExists;
  final String? applicationVersion, serverOrigin;
}

final class RuntimeOverlayFacts {
  const RuntimeOverlayFacts({
    this.windowState,
    this.hotkeyBinding,
    this.hotkeyState,
    this.presetName,
    this.renderMode,
  });
  final String? windowState, hotkeyBinding, hotkeyState, presetName, renderMode;
}

final class RuntimeStartupFacts {
  const RuntimeStartupFacts({
    required this.launchAtStartup,
    required this.startMinimized,
    required this.keepRunningInBackground,
  });
  final bool launchAtStartup, startMinimized, keepRunningInBackground;
}

final class RuntimeStatusView {
  const RuntimeStatusView({
    this.busy = false,
    this.loaded = false,
    this.installation,
    this.overlay,
    this.startup,
  });
  final bool busy, loaded;
  final RuntimeInstallationFacts? installation;
  final RuntimeOverlayFacts? overlay;
  final RuntimeStartupFacts? startup;
  bool get incomplete =>
      loaded && (installation == null || overlay == null || startup == null);
}

/// One on-demand read of existing owners, not a second settings store or poller.
final class RuntimeStatusController extends ValueNotifier<RuntimeStatusView> {
  RuntimeStatusController({
    required this.readInstallation,
    required this.readOverlay,
    required this.readStartup,
    this.sourceTimeout = const Duration(seconds: 15),
  }) : super(const RuntimeStatusView());
  final Duration sourceTimeout;
  final Future<RuntimeInstallationFacts?> Function() readInstallation;
  final Future<RuntimeOverlayFacts?> Function() readOverlay;
  final Future<RuntimeStartupFacts?> Function() readStartup;
  bool _disposed = false;

  Future<void> refresh() async {
    if (_disposed || value.busy) return;
    value = const RuntimeStatusView(busy: true);
    // A failed source must not hide facts read successfully from other owners.
    final installation = _read(readInstallation);
    final overlay = _read(readOverlay);
    final startup = _read(readStartup);
    final next = RuntimeStatusView(
      loaded: true,
      installation: await installation,
      overlay: await overlay,
      startup: await startup,
    );
    if (!_disposed) value = next;
  }

  Future<T?> _read<T>(Future<T?> Function() reader) async {
    try {
      return await reader().timeout(sourceTimeout);
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
