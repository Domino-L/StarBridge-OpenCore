import '../../platform/bridge/bridge_client_session.dart';
import 'room_chat_module.dart';
import 'room_preset_port.dart';

final class BridgeRoomPresets {
  BridgeRoomPresets(this.session);
  final BridgeClientSession session;
  bool get available =>
      session.hostCapabilities.contains('overlay.presetSharing') &&
      session.hostCapabilities.contains('partyRooms.chatAttachments');

  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> data,
  ) async {
    if (!available) throw const RoomChatFailure('hostUnavailable');
    try {
      final result = await session.request(
        name,
        payload: {'schemaVersion': 1, ...data},
      );
      if (result.payload['schemaVersion'] != 1) throw const FormatException();
      return result.payload;
    } on BridgeClientException catch (error) {
      throw RoomChatFailure(switch (error.code) {
        'overlay.revision_conflict' ||
        'overlay.workspace_revision_conflict' => 'presetChanged',
        'overlay.shared_preset_invalid' => 'presetInvalid',
        _ =>
          data['action'] == 'importSharedPreset'
              ? 'presetImportUnknown'
              : 'unavailable',
      });
    } on Object {
      throw RoomChatFailure(
        data['action'] == 'importSharedPreset'
            ? 'presetImportUnknown'
            : 'invalidResponse',
      );
    }
  }

  Future<RoomPresetCatalog> read() async {
    final result = await _request('overlay.getWorkspace', const {});
    return RoomPresetCatalog(result['revision'] as int, [
      for (final preset in result['presets'] as List)
        RoomPresetChoice(
          (preset as Map)['id'] as String,
          preset['name'] as String,
        ),
    ]);
  }

  Future<Map<String, Object?>> export(String id, int revision) async {
    final result = await _request('overlay.updateWorkspace', {
      'action': 'exportSharedPreset',
      'expectedRevision': revision,
      'presetId': id,
    });
    return Map<String, Object?>.from(result['attachment'] as Map);
  }

  Future<String> import(String package, int revision) async {
    final result = await _request('overlay.updateWorkspace', {
      'action': 'importSharedPreset',
      'expectedRevision': revision,
      'package': package,
    });
    return result['name'] as String;
  }
}
