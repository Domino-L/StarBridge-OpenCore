import '../../platform/bridge/bridge_client_session.dart';

enum ClientLicenseState { ready, missing, unreadable, unavailable }

final class ClientLicenseDocument {
  const ClientLicenseDocument(this.state, [this.text]);
  final ClientLicenseState state;
  final String? text;
}

typedef ClientLicenseRead = Future<ClientLicenseDocument> Function();

final class BridgeClientLicense {
  BridgeClientLicense(this.session, {required this.available});
  final BridgeClientSession session;
  final bool available;

  Future<ClientLicenseDocument> read() async {
    if (!available) {
      return const ClientLicenseDocument(ClientLicenseState.unavailable);
    }
    final response = await session.request(
      'legal.getClientLicense',
      payload: const {'schemaVersion': 1},
    );
    final p = response.payload;
    final text = p['text'];
    if (p.length != 3 ||
        !p.containsKey('text') ||
        p['schemaVersion'] != 1 ||
        !const {'ready', 'missing', 'unreadable'}.contains(p['state']) ||
        (p['state'] == 'ready'
            ? text is! String ||
                  text.trim().isEmpty ||
                  text.length > 65536 ||
                  RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]')
                      .hasMatch(text)
            : text != null)) {
      throw const FormatException('Incompatible license document.');
    }
    return ClientLicenseDocument(
      ClientLicenseState.values.byName(p['state'] as String),
      text as String?,
    );
  }
}
