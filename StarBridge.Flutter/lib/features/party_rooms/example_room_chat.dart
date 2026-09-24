import 'room_chat_module.dart';
import '../communities/community_invitation_attachment.dart';
import 'room_preset_port.dart';

import 'dart:convert';

final class ExampleRoomChat implements RoomChatPort, RoomPresetPort {
  final _rooms = <String, List<RoomChatMessage>>{};
  final _presets = <String, Map<String, Object?>>{
    'example-preset': {
      'Version': 1,
      'Name': '示例浮层预设',
      'Settings': '0,CallsignAndGameName,0,0,0',
      'Layout': 'Notice,0.3,0,0.4,0.06;Squads,0,0.4,0.16,0.12;Members,0,0.52,0.16,0.2;Chat,0,0.72,0.16,0.16',
    },
  };
  int _revision = 1;
  @override
  bool get presetsAvailable => true;
  @override
  Future<RoomPresetCatalog> readPresets() async =>
      RoomPresetCatalog(_revision, [
        for (final entry in _presets.entries)
          RoomPresetChoice(entry.key, entry.value['Name'] as String),
      ]);
  @override
  Future<Map<String, Object?>> exportPreset(String id, int revision) async {
    if (revision != _revision || !_presets.containsKey(id)) {
      throw const RoomChatFailure('presetChanged');
    }
    return {
      'kind': 'overlay_preset',
      'title': _presets[id]!['Name'],
      'summary': '示例预设 · 仅在示例场景中使用',
      'overlayPresetPackage': jsonEncode(_presets[id]),
    };
  }

  @override
  Future<String> importPreset(String package, int revision) async {
    if (revision != _revision) throw const RoomChatFailure('presetChanged');
    final value = Map<String, Object?>.from(jsonDecode(package) as Map);
    if (value['Version'] != 1 || value['Name'] is! String) {
      throw const RoomChatFailure('presetInvalid');
    }
    final name = '${value['Name']} (${_presets.length + 1})';
    _presets['import-${++_revision}'] = {...value, 'Name': name};
    return name;
  }

  @override
  Future<RoomChatMessage> sendPreset(
    String roomId,
    String text,
    Map<String, Object?> attachment,
  ) => _send(roomId, text, attachment);
  @override
  bool get available => true;
  List<RoomChatMessage> _messages(String id) => _rooms.putIfAbsent(
    id,
    () => [
      RoomChatMessage(
        sequence: 1,
        id: '$id-1',
        sender: '示例房主 (Example_Host)',
        text: '欢迎加入房间，出发前请确认路线。',
        communityInvitation: const CommunityInvitationAttachment(
          title: '组织邀请 · 新手互助',
          summary: '查看示例组织详情后决定是否加入。',
          inviteCode: 'EXAMPLE-ORG',
        ),
        time: DateTime.now().toUtc(),
      ),
      RoomChatMessage(
        sequence: 2,
        id: '$id-2',
        sender: '示例成员 (Example_Member)',
        isSelf: true,
        text: '收到，准备好后在这里回复。',
        time: DateTime.now().toUtc(),
      ),
    ],
  );
  @override
  Future<RoomChatPage> read(
    String roomId, {
    int after = 0,
    int before = 0,
  }) async {
    final all = _messages(roomId);
    final candidates = all
        .where(
          (message) =>
              before > 0 ? message.sequence < before : message.sequence > after,
        )
        .toList();
    final page = after > 0
        ? candidates.take(50).toList()
        : candidates
              .skip(candidates.length > 50 ? candidates.length - 50 : 0)
              .toList();
    return RoomChatPage(
      page,
      all.last.sequence,
      page.isNotEmpty && page.first.sequence > all.first.sequence,
    );
  }

  @override
  Future<RoomChatMessage> send(String roomId, String text) async {
    return _send(roomId, text, null);
  }

  Future<RoomChatMessage> _send(
    String roomId,
    String text,
    Map<String, Object?>? attachment,
  ) async {
    if ((text.trim().isEmpty && attachment == null) || text.length > 300) {
      throw const RoomChatFailure('invalidInput');
    }
    final messages = _messages(roomId);
    final sequence = messages.last.sequence + 1;
    final message = RoomChatMessage(
      sequence: sequence,
      id: '$roomId-$sequence',
      sender: '示例成员 (Example_Member)',
      isSelf: true,
      text: text,
      time: DateTime.now().toUtc(),
      attachment: attachment,
    );
    messages.add(message);
    return message;
  }
}
