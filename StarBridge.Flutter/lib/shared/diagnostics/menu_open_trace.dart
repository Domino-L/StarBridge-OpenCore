import 'loading_metrics.dart';

/// Fixed menu phases and local numeric generations only. No channel payloads
/// enter diagnostics, and ordinary runs create no recorder or observer.
abstract final class MenuOpenTrace {
  static void request(int id) => _mark(LoadingMenuPhase.request, id);
  static void preferences(int id) =>
      _mark(LoadingMenuPhase.preferencesFinished, id);
  static void recovery(int id) => _mark(LoadingMenuPhase.recoveryFinished, id);
  static void hostReport(int id) =>
      _mark(LoadingMenuPhase.hostReportFinished, id);
  static void nativeRequest(int id) =>
      _mark(LoadingMenuPhase.nativeRequest, id);
  static void nativeReply(int id, int opening) => LoadingMetrics.current
      ?.menuOpening(LoadingMenuPhase.nativeReply, id, opening: opening);
  static void settled(int id, bool visible) => LoadingMetrics.current
      ?.menuOpening(LoadingMenuPhase.settled, id, visible: visible);

  static void windowState(int id, Object? state, [Object? reason]) {
    final phase = switch (state) {
      'visible' => LoadingMenuPhase.visible,
      'hidden' => LoadingMenuPhase.hidden,
      'unavailable' => LoadingMenuPhase.unavailable,
      _ => null,
    };
    if (phase == null) return;
    // Native sends a fixed reason code with hidden; anything else is dropped.
    final code = phase == LoadingMenuPhase.hidden
        ? LoadingMenuHideReason.values
              .where((r) => r.name == reason)
              .firstOrNull
        : null;
    LoadingMetrics.current?.menuOpening(phase, id, reason: code);
  }

  static void _mark(LoadingMenuPhase phase, int id) =>
      LoadingMetrics.current?.menuOpening(phase, id);
}
