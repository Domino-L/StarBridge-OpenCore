import 'dart:async';

import '../../shared/diagnostics/loading_metrics.dart';
import 'hangar_read_diagnostics.dart';

/// Static composition owners only, never an account, route parameter or key.
enum HangarReadOrigin { unknown, feature, profile, menuProfile }

Future<T> observeHangarRead<T>(
  HangarReadOrigin origin,
  HangarReadStage stage,
  Future<T> Function() action,
) {
  final metrics = LoadingMetrics.current;
  if (metrics == null || metrics.stopped) return action();
  final completion = Completer<Object?>();
  metrics.observe(
    'hangar.${origin.name}.${stage.name}',
    completion.future,
    transport: false,
  );
  try {
    return action().then(
      (value) {
        completion.complete();
        return value;
      },
      onError: (Object error, StackTrace stack) {
        completion.completeError(error, stack);
        Error.throwWithStackTrace(error, stack);
      },
    );
  } catch (error, stack) {
    completion.completeError(error, stack);
    rethrow;
  }
}
