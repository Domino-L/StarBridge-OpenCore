import '../bridge/bridge_client_session.dart';
import '../bridge/bridge_connection.dart';

abstract interface class NativeHostConnector {
  Future<NativeHostLease> open();
}

abstract interface class NativeHostLease {
  BridgeClientSession get session;

  Future<NativeHostTermination> get terminated;

  Future<void> close();
}

abstract interface class NativeHostPlatformPort {
  Future<NativeHostPlatformLease> start({required String pipeName});
}

abstract interface class NativeHostPlatformLease {
  BridgeConnection get connection;

  Future<NativeHostTermination> get terminated;

  Future<void> close();
}

final class NativeHostTermination {
  const NativeHostTermination({required this.code, this.exitCode});

  final String code;
  final int? exitCode;
}

final class NativeHostConnectionException implements Exception {
  const NativeHostConnectionException(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => detail == null
      ? 'NativeHostConnectionException: $code'
      : 'NativeHostConnectionException: $code ($detail)';
}
