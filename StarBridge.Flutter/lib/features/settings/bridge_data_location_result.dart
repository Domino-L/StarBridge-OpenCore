import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';

final class DataLocationMigrationResult {
  const DataLocationMigrationResult({
    required this.nonce,
    required this.state,
    required this.source,
    required this.destination,
  });
  final String nonce;
  final String state;
  final String source;
  final String destination;
}

final class BridgeDataLocationResult {
  const BridgeDataLocationResult(this._session);
  final BridgeClientSession _session;

  Future<DataLocationMigrationResult?> read() async {
    final payload = (await _session.request(
      'dataLocation.getMigrationResult',
      payload: const {'schemaVersion': 1},
    )).payload;
    if (payload.length != 6 ||
        payload['schemaVersion'] != 1 ||
        !const {
          'none',
          'migrated',
          'migration-failed',
        }.contains(payload['state'])) {
      throw const BridgeFormatException('Migration result is incompatible.');
    }
    if (payload['state'] == 'none') {
      if (payload['nonce'] != null ||
          payload['source'] != null ||
          payload['destination'] != null ||
          payload['completedAt'] != null) {
        throw const BridgeFormatException('Migration result is inconsistent.');
      }
      return null;
    }
    final nonce = payload['nonce'];
    final source = payload['source'];
    final destination = payload['destination'];
    final completedAt = payload['completedAt'];
    if (nonce is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce) ||
        !_validPath(source) ||
        !_validPath(destination) ||
        completedAt is! String ||
        DateTime.tryParse(completedAt) == null) {
      throw const BridgeFormatException('Migration result is invalid.');
    }
    return DataLocationMigrationResult(
      nonce: nonce,
      state: payload['state'] as String,
      source: source as String,
      destination: destination as String,
    );
  }

  Future<void> acknowledge(String nonce) async {
    final payload = (await _session.request(
      'dataLocation.acknowledgeMigrationResult',
      payload: {'schemaVersion': 1, 'nonce': nonce},
    )).payload;
    if (payload.length != 2 ||
        payload['schemaVersion'] != 1 ||
        payload['acknowledged'] != true) {
      throw const BridgeFormatException('Migration acknowledgement failed.');
    }
  }

  static bool _validPath(Object? value) =>
      value is String &&
      value.length <= 32767 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) &&
      RegExp(r'^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)').hasMatch(value);
}
