import '../../platform/bridge/bridge_client_session.dart';
import 'runtime_status_controller.dart';

final class BridgeRuntimeFacts {
  BridgeRuntimeFacts(this.session);
  final BridgeClientSession session;

  Future<RuntimeInstallationFacts> read() async {
    final response = await session.request(
      'diagnostics.getRuntimeFacts',
      payload: const {'schemaVersion': 1},
    );
    final p = response.payload;
    final version = p['applicationVersion'], origin = p['serverOrigin'];
    if (p.length != 6 ||
        p['schemaVersion'] != 1 ||
        !p.keys.toSet().containsAll(const {
          'schemaVersion',
          'applicationVersion',
          'dataDirectory',
          'imageCacheDirectory',
          'imageCacheExists',
          'serverOrigin',
        }) ||
        !_path(p['dataDirectory']) ||
        !_path(p['imageCacheDirectory']) ||
        p['imageCacheExists'] is! bool ||
        version != null &&
            (version is! String ||
                version.length > 96 ||
                !RegExp(
                  r'^[0-9]+(?:\.[0-9]+){1,3}(?:[-+][A-Za-z0-9][A-Za-z0-9.+-]*)?$',
                ).hasMatch(version)) ||
        origin != null && !_origin(origin)) {
      throw const FormatException('Incompatible runtime facts.');
    }
    return RuntimeInstallationFacts(
      dataDirectory: p['dataDirectory'] as String,
      imageCacheDirectory: p['imageCacheDirectory'] as String,
      imageCacheExists: p['imageCacheExists'] as bool,
      applicationVersion: version as String?,
      serverOrigin: origin as String?,
    );
  }

  static bool _path(Object? value) =>
      value is String &&
      value.length <= 32767 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) &&
      RegExp(r'^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)').hasMatch(value);

  static bool _origin(Object? value) {
    if (value is! String ||
        value.length > 4096 ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
      return false;
    }
    final uri = Uri.tryParse(value);
    return uri != null &&
        const {'https', 'http'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.path.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }
}
