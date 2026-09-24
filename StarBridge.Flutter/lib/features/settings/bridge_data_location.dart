import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'bridge_application_support.dart';
import 'data_location_port.dart';

final class BridgeDataLocation implements DataLocationMigrationPort {
  BridgeDataLocation(this._session)
    : migrationAvailable =
          _session.hostCapabilities.contains('dataLocation.chooseMigration') &&
          _session.hostCapabilities.contains('dataLocation.confirmMigration');
  final BridgeClientSession _session;
  @override
  final bool migrationAvailable;

  @override
  Future<DataLocation> read() async {
    final response = await _session.request(
      'diagnostics.getDataLocation',
      payload: const {'schemaVersion': 1},
    );
    final payload = response.payload;
    final path = payload['path'];
    final exists = payload['exists'];
    if (payload.length != 3 ||
        payload['schemaVersion'] != 1 ||
        path is! String ||
        path.length > 32767 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
        !RegExp(r'^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)').hasMatch(path) ||
        exists is! bool) {
      throw const BridgeFormatException(
        'Data location response is incompatible.',
      );
    }
    return DataLocation(path: path, exists: exists);
  }

  @override
  Future<void> open() => BridgeApplicationSupport(_session).openDataDirectory();

  @override
  Future<DataLocationMigrationChoice?> chooseMigration() async {
    if (!migrationAvailable) throw StateError('unavailable');
    final payload = (await _session.request(
      'dataLocation.chooseMigration',
      payload: const {'schemaVersion': 1},
      timeout: const Duration(minutes: 3),
    )).payload;
    if (payload.length != 5 ||
        payload['schemaVersion'] != 1 ||
        !const {
          'unchanged',
          'confirmation-required',
        }.contains(payload['state'])) {
      throw const BridgeFormatException('Migration choice is incompatible.');
    }
    if (payload['state'] == 'unchanged') {
      if (payload['ticket'] != null ||
          payload['source'] != null ||
          payload['destination'] != null) {
        throw const BridgeFormatException('Migration choice is inconsistent.');
      }
      return null;
    }
    final ticket = payload['ticket'];
    final source = payload['source'];
    final destination = payload['destination'];
    if (ticket is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(ticket) ||
        !_validPath(source) ||
        !_validPath(destination) ||
        source == destination) {
      throw const BridgeFormatException('Migration choice is invalid.');
    }
    return DataLocationMigrationChoice(
      ticket: ticket,
      source: source as String,
      destination: destination as String,
    );
  }

  @override
  Future<void> confirmMigration(String ticket) async {
    if (!migrationAvailable || !RegExp(r'^[0-9a-f]{32}$').hasMatch(ticket)) {
      throw StateError('unavailable');
    }
    final payload = (await _session.request(
      'dataLocation.confirmMigration',
      payload: {'schemaVersion': 1, 'ticket': ticket},
      timeout: const Duration(seconds: 35),
    )).payload;
    if (payload.length != 2 ||
        payload['schemaVersion'] != 1 ||
        payload['accepted'] != true) {
      throw const BridgeFormatException('Migration handoff was not confirmed.');
    }
  }

  static bool _validPath(Object? value) =>
      value is String &&
      value.length <= 32767 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) &&
      RegExp(r'^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)').hasMatch(value);
}
