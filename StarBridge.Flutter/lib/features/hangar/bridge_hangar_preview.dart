import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import 'hangar_reader_port.dart';

final class BridgeHangarPreview implements HangarPreviewPort {
  BridgeHangarPreview(this._session);
  final BridgeClientSession _session;
  BridgeAccountContext? _account;
  int? _generation;
  String? _operation;

  Future<void> _resolveAccount() async {
    final account = await _session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
      timeout: const Duration(seconds: 60),
    );
    if (!hasRelayAccount(account) || account.accountContext == null) {
      throw const HangarReaderFailure('accountChanged');
    }
    _account = account.accountContext;
    _generation = account.sessionGeneration;
  }

  @override
  Future<String> prepare() async {
    await _resolveAccount();
    final profile = await _request('browserProfile');
    final key = profile['profileKey'];
    if (key is! String || !RegExp(r'^[0-9A-F]{64}$').hasMatch(key)) {
      throw const HangarReaderFailure('accountChanged');
    }
    return key;
  }

  @override
  Future<Map<String, Object?>> begin() async {
    await _resolveAccount();
    final view = await _request('begin');
    _operation = view['operationId'] as String;
    return view;
  }

  Future<Map<String, Object?>> _request(
    String action, [
    Map<String, Object?> payload = const {},
  ]) async {
    if (_account == null || _generation != _session.activeGeneration) {
      throw const HangarReaderFailure('accountChanged');
    }
    final response = await _session.request(
      'hangarReader.$action',
      accountContext: _account,
      payload: {
        'schemaVersion': 1,
        if (_operation != null) 'operationId': _operation,
        ...payload,
      },
    );
    if (_generation != _session.activeGeneration ||
        response.payload['schemaVersion'] != 1) {
      throw const HangarReaderFailure('accountChanged');
    }
    return response.payload;
  }

  @override
  Future<Map<String, Object?>> verify(Map<String, Object?> observation) =>
      _request('verify', observation);
  @override
  Future<Map<String, Object?>> observe(Map<String, Object?> observation) =>
      _request('observe', observation);
  @override
  Future<void> cancel() async {
    if (_operation == null) return;
    try {
      await _request('cancel');
    } on Object {
      /* Cancellation is best effort after disconnect. */
    }
    _operation = null;
  }
}

final class UnavailableHangarPreview implements HangarPreviewPort {
  @override
  Future<String> prepare() async =>
      throw const HangarReaderFailure('hostUnavailable');
  @override
  Future<Map<String, Object?>> verify(Map<String, Object?> observation) =>
      begin();
  @override
  Future<Map<String, Object?>> begin() async =>
      throw const HangarReaderFailure('hostUnavailable');
  @override
  Future<Map<String, Object?>> observe(Map<String, Object?> observation) =>
      begin();
  @override
  Future<void> cancel() async {}
}
