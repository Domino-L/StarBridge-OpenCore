import '../../platform/bridge/bridge_client_session.dart';

abstract interface class HelpSupportPort {
  Future<Map<String, dynamic>> read(String name);
  Future<void> send(String contact, String message);
}

class BridgeHelpSupport implements HelpSupportPort {
  BridgeHelpSupport(this.session);
  final BridgeClientSession? session;
  Future<Map<String, dynamic>> _request(
    String name,
    Map<String, dynamic> payload,
  ) async {
    final host = session;
    if (host == null || !host.hostCapabilities.contains(name)) {
      throw StateError('Support unavailable');
    }
    return (await host.request(
      name,
      payload: payload,
      timeout: const Duration(seconds: 20),
    )).payload;
  }

  @override
  Future<Map<String, dynamic>> read(String name) =>
      _request(name, {'schemaVersion': 1});
  @override
  Future<void> send(String contact, String message) async {
    final result = await _request('helpSupport.feedback', {
      'schemaVersion': 1,
      'contact': contact,
      'message': message,
    });
    if (result['schemaVersion'] != 1 ||
        result['sent'] != true ||
        result.length != 2) {
      throw const FormatException('Unconfirmed feedback');
    }
  }
}
