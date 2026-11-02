import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';

/// Auxiliary-engine handshake and presentation evidence. Never bootstraps an
/// account, reveals a window, or changes the native first-frame timeout.
abstract final class MenuSurfaceLoading {
  static Future<void> ready(
    MethodChannel channel,
    void Function(Object?) accept,
  ) async {
    try {
      accept(await channel.invokeMethod<Object?>('ready'));
    } on PlatformException {
      // Native first-frame recovery owns an unavailable/unconfigured surface.
    } on MissingPluginException {
      // No standalone fallback to the account bootstrap.
    }
  }

  static void snapshot(int opening, bool wanted) {
    final metrics = LoadingMetrics.current;
    metrics?.menuSurface(opening: opening, wanted: wanted);
    if (wanted) {
      metrics?.route('/menu');
      metrics?.auxiliaryOpening(
        LoadingAuxiliarySurface.menu,
        LoadingAuxiliaryPhase.snapshot,
        opening,
      );
    }
  }

  static Widget content({required bool wanted, required Widget child}) =>
      LoadingContentProbe(
        route: '/menu',
        status: wanted
            ? LoadingContentStatus.data
            : LoadingContentStatus.waiting,
        items: wanted ? 1 : 0,
        child: child,
      );
}
