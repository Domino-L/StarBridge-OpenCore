import '../../platform/bridge/bridge_client_session.dart';
import 'hangar_inventory_port.dart';

/// Test identity selection is confined to the dedicated loopback workspace in the Host.
class BridgeHangarInventory implements HangarInventoryPort {
  BridgeHangarInventory(this.session);
  final BridgeClientSession session;
  Future<Map<String, Object?>> _call(
    String action,
    Map<String, Object?> body,
  ) async {
    try {
      return (await session.request(
        'hangarSandbox.$action',
        payload: body,
        timeout: const Duration(seconds: 30),
      )).payload;
    } on BridgeClientException catch (error) {
      throw HangarInventoryFailure(error.code.replaceFirst('hangar.', ''));
    }
  }

  @override
  Future<bool> available() async {
    try {
      return (await _call('status', {}))['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<HangarInventorySnapshot> read(String account) async =>
      _snapshot(await _call('read', {'testAccount': account}));
  @override
  Future<HangarInventoryImport> preview(
    String account,
    String scenario,
    String key,
    int revision,
  ) async {
    final record = await _call('preview', {
      'testAccount': account,
      'scenario': scenario,
      'key': key,
      'baseRevision': revision,
    });
    final value = record['preview'] as Map;
    final diff = value['diff'] as Map;
    return HangarInventoryImport(
      value['id'] as String,
      value['baseRevision'] as int,
      value['digest'] as String,
      _ships(value['ships']),
      (diff['added'] as List).length,
      (diff['removed'] as List).length,
      (diff['retained'] as List).length,
      (value['ambiguous'] as List).isNotEmpty,
    );
  }

  @override
  Future<HangarInventorySnapshot> commit(
    String account,
    HangarInventoryImport preview,
    String key,
    bool clear,
  ) async => _snapshot(
    await _call('commit', {
      'testAccount': account,
      'importId': preview.id,
      'key': key,
      'expectedRevision': preview.revision,
      'digest': preview.digest,
      'confirmRemovalOfAll': clear,
    }),
  );
  @override
  Future<HangarInventorySnapshot?> result(String account, String id) async {
    final result = await _call('result', {
      'testAccount': account,
      'importId': id,
    });
    return result['committed'] is Map
        ? _snapshot(result['committed'] as Map)
        : null;
  }

  static HangarInventorySnapshot _snapshot(Map value) =>
      HangarInventorySnapshot(
        value['revision'] as int,
        DateTime.tryParse(value['savedAt'] as String? ?? ''),
        _ships(value['ships']),
      );
  static List<HangarInventoryShip> _ships(Object? value) => List.unmodifiable(
    (value as List).map((s) {
      final ship = s as Map;
      final presentation = ship['presentation'] as Map? ?? {};
      final names = presentation['names'] as Map? ?? {};
      return HangarInventoryShip(
        ship['id'] as String,
        ship['rawTitle'] as String,
        names['zhHans'] as String?,
        names['zhHant'] as String?,
        presentation['combatSize'] as String?,
      );
    }),
  );
}
