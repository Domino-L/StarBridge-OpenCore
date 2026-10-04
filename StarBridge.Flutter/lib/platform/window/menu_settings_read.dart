import '../bridge/bridge_client_session.dart';
import '../bridge/bridge_envelope.dart';

/// Metadata reads share the Bridge's normal deadline, not a three-second
/// interaction ACK deadline. Only an explicit transient Host rejection gets
/// one retry; writes, malformed data, timeouts and retired scopes do not.
Future<BridgeEnvelope> readMenuSettings(
  BridgeClientSession session,
  String name, {
  Map<String, Object?> payload = const {'schemaVersion': 1},
  bool Function()? isCurrent,
  String unavailableCode = 'menuSettings.session_unavailable',
  void Function(BridgeRequestOperation)? onBegin,
  void Function(BridgeRequestOperation)? onEnd,
}) async {
  if (!const {
    'applicationPreferences.menu.get',
    'menuBrowserResume.read',
    'menuScreenshotDirectory.read',
    'menuHotkey.settings.get',
  }.contains(name)) {
    throw ArgumentError.value(name, 'name', 'Only menu settings reads allowed');
  }
  final generation = session.activeGeneration;
  void current() {
    if (session.activeGeneration != generation) {
      throw BridgeStaleGenerationException(
        generation,
        session.activeGeneration,
      );
    }
    if (isCurrent != null && !isCurrent()) {
      throw BridgeClientException(unavailableCode);
    }
  }

  for (var attempt = 0; ; attempt++) {
    current();
    final operation = session.beginRequest(name, payload: payload);
    onBegin?.call(operation);
    try {
      final response = await operation.future;
      current();
      return response;
    } on BridgeRemoteException catch (error) {
      if (attempt != 0 ||
          !error.retryable ||
          !const {
            'bridge.backpressure',
            'bridge.disconnected',
          }.contains(error.code)) {
        rethrow;
      }
    } finally {
      onEnd?.call(operation);
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
