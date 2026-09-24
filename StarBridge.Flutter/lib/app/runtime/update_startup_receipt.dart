import '../../platform/bridge/bridge_client_session.dart';

/// Reports a rendered frame for this Host lease, never a synthetic success.
Future<bool> reportUpdateStartupReceipt(
  BridgeClientSession session, {
  required bool Function() isCurrent,
  Duration retryDelay = const Duration(seconds: 1),
  Duration requestTimeout = const Duration(seconds: 10),
}) async {
  // Account restoration can invalidate an in-flight device-level request.
  // Retry on the same live Host only; six ten-second attempts plus delays stay
  // below the installer's two-minute deadline. Failure never confirms startup.
  for (var attempt = 0; attempt < 6; attempt++) {
    if (!isCurrent()) return false;
    try {
      final response = await session.request(
        'applicationUpdates.firstFrameReady',
        payload: const {'schemaVersion': 1},
        timeout: requestTimeout,
      );
      return isCurrent() &&
          response.payload['schemaVersion'] == 1 &&
          response.payload['reported'] == true;
    } on BridgeClientException catch (error) {
      if (error is BridgeDisconnectedException ||
          (error is! BridgeStaleGenerationException && !error.retryable)) {
        return false;
      }
    } on Object {
      return false;
    }
    if (attempt < 5 && isCurrent()) await Future<void>.delayed(retryDelay);
  }
  return false;
}
