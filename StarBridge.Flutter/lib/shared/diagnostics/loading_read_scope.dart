import 'dart:async';

import 'loading_metrics.dart';

/// Explicit passive provenance only. This neither grants IO nor changes work.
T backgroundLoadingRead<T>(T Function() work) {
  final metrics = LoadingMetrics.current;
  return metrics == null ? work() : metrics.background(work);
}
/// Lifecycle dispatch need not invoke a callback in its registration zone.
/// Capture only the optional recorder; preserve the dispatcher's error handling.
/// Ordinary runs retain the exact original callback and allocate no recorder.
void Function() backgroundLoadingCallback(void Function() action) {
  final metrics = LoadingMetrics.current;
  if (metrics == null) return action;
  return () => runZoned(
    () => metrics.background(action),
    zoneValues: {loadingMetricsZoneKey: metrics},
  );
}
