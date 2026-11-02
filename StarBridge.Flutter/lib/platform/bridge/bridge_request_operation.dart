import 'bridge_envelope.dart';

/// Read-only presentation owned by one unfinished transport request.
/// It never completes that request or supplies account authority.
final class BridgeDisplayProgress {
  const BridgeDisplayProgress(this.eventName, this.accept);
  final String eventName;
  final void Function(BridgeEnvelope frame) accept;
}

final class BridgeRequestOperation {
  BridgeRequestOperation(this.future, this._cancel, {this.correlationId});

  final Future<BridgeEnvelope> future;
  final String? correlationId;
  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

class BridgeClientException implements Exception {
  const BridgeClientException(this.code, {this.retryable = false});

  final String code;
  final bool retryable;

  @override
  String toString() => 'BridgeClientException($code)';
}

final class BridgeRemoteException extends BridgeClientException {
  const BridgeRemoteException(super.code, {super.retryable});
}

final class BridgeAccountContextRequiredException
    extends BridgeClientException {
  const BridgeAccountContextRequiredException(this.requestName)
    : super('bridge.account_context_required');

  final String requestName;
}

final class BridgeTimeoutException extends BridgeClientException {
  const BridgeTimeoutException(this.requestName)
    : super('bridge.timeout', retryable: true);

  final String requestName;
}

final class BridgeCancelledException extends BridgeClientException {
  const BridgeCancelledException(this.requestName) : super('bridge.cancelled');

  final String requestName;
}

final class BridgeDisconnectedException extends BridgeClientException {
  const BridgeDisconnectedException()
    : super('bridge.disconnected', retryable: true);
}

final class BridgeStaleGenerationException extends BridgeClientException {
  const BridgeStaleGenerationException(
    this.requestGeneration,
    this.activeGeneration,
  ) : super('bridge.stale_generation');

  final int requestGeneration;
  final int activeGeneration;
}
