import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_account_access.dart';

/// Local display data only; never returns action refs, receipts or permissions.
abstract interface class MenuChatArchive {
  Future<List<Map<String, Object?>>> load(String kind, String reference);
  Future<void> clear(String kind, String reference);
}

final class BridgeMenuChatArchive implements MenuChatArchive {
  BridgeMenuChatArchive(this.session);
  final BridgeClientSession session;
  Future<Map<String, Object?>> _request(
    String kind,
    String reference,
    String action,
  ) async {
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (!hasRelayAccount(account) || account.accountContext == null) {
      throw StateError('account');
    }
    final response = await session.request(
      kind == 'private' ? 'directMessages.read' : 'communities.chat',
      accountContext: account.accountContext,
      payload: {
        'schemaVersion': 1,
        'targetRef': reference,
        'localHistory': action,
        if (kind != 'private') ...{'after': 0, 'before': 0},
      },
    );
    if (response.payload['schemaVersion'] != 1 ||
        response.payload['error'] != null) {
      throw StateError('archive');
    }
    return response.payload;
  }

  @override
  Future<void> clear(String kind, String reference) async {
    await _request(kind, reference, 'clear');
  }

  @override
  Future<List<Map<String, Object?>>> load(String kind, String reference) async {
    final data = await _request(kind, reference, 'read');
    final rows = data['rows'];
    if (rows is! List || rows.length > 50) throw const FormatException();
    return rows.map((raw) {
      if (raw is! Map ||
          raw['text'] is! String ||
          (raw['text'] as String).length > 4096 ||
          raw['name'] is! String ||
          (raw['name'] as String).length > 512 ||
          raw['self'] is! bool ||
          raw['attachment'] is! bool ||
          raw['time'] is! String ||
          DateTime.tryParse(raw['time'] as String) == null) {
        throw const FormatException();
      }
      return <String, Object?>{
        'text': raw['text'],
        'name': raw['name'],
        'self': raw['self'],
        'attachment': raw['attachment'],
        'time': raw['time'],
      };
    }).toList();
  }
}
