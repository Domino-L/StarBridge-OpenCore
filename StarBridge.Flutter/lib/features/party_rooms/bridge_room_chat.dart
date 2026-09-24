import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_account_access.dart';
import '../communities/community_invitation_attachment.dart';
import 'room_chat_module.dart';
import 'room_invitations.dart';
import 'room_preset_port.dart';
import 'bridge_room_presets.dart';
import '../direct_messages/bridge_direct_messages.dart' show inlineAvatar;

final class BridgeRoomChat implements RoomChatPort, RoomPresetPort {
  BridgeRoomChat(this.session);
  final BridgeClientSession session;
  late final _presets = BridgeRoomPresets(session);
  @override
  bool get presetsAvailable => available && _presets.available;
  @override
  Future<RoomPresetCatalog> readPresets() => _presets.read();
  @override
  Future<Map<String, Object?>> exportPreset(String id, int revision) =>
      _presets.export(id, revision);
  @override
  Future<String> importPreset(String package, int revision) =>
      _presets.import(package, revision);
  @override
  Future<RoomChatMessage> sendPreset(
    String roomId,
    String text,
    Map<String, Object?> attachment,
  ) {
    if (!presetsAvailable) throw const RoomChatFailure('hostUnavailable');
    return _send(roomId, text, attachment);
  }

  @override
  bool get available => session.hostCapabilities.contains('partyRooms.chat');
  Future<Map<String, Object?>> _request(
    String operation,
    Map<String, Object?> data,
  ) async {
    if (!available) throw const RoomChatFailure('hostUnavailable');
    var sent = false;
    try {
      final account = await session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      if (!hasRelayAccount(account) || account.accountContext == null) {
        throw const RoomChatFailure('identityUnavailable');
      }
      sent = operation == 'chatSend';
      final result = await session.request(
        'partyRooms.execute',
        accountContext: account.accountContext,
        payload: {'schemaVersion': 1, 'operation': operation, 'data': data},
      );
      if (result.payload['schemaVersion'] != 1) throw const FormatException();
      if (result.payload['status'] == 'rejected') {
        throw RoomChatFailure(
          result.payload['error'] as String? ?? 'chatRejected',
        );
      }
      return result.payload;
    } on RoomChatFailure {
      rethrow;
    } on BridgeClientException catch (error) {
      throw RoomChatFailure(switch (error.code) {
        'party_rooms.identity_unavailable' ||
        'account.reauthorization_required' => 'identityUnavailable',
        'party_rooms.forbidden' => 'forbidden',
        'party_rooms.data_invalid' => 'invalidInput',
        'party_rooms.command_unavailable' => 'unavailable',
        _ => sent ? 'outcomeUnknown' : 'unavailable',
      });
    } on Object {
      throw RoomChatFailure(sent ? 'outcomeUnknown' : 'invalidResponse');
    }
  }

  @override
  Future<RoomChatPage> read(
    String roomId, {
    int after = 0,
    int before = 0,
  }) async {
    final result = await _request('chatRead', {
      'roomId': roomId,
      'after': after,
      'before': before,
    });
    try {
      if (result['status'] != 'chat') throw const FormatException();
      final data = result['chat'] as Map;
      final raw = data['messages'] as List;
      if (raw.length > 50) throw const FormatException();
      final messages = raw
          .map((item) => parseRoomChatMessage(item as Map))
          .toList();
      final latest = data['latestSequence'] as int;
      if (latest < 0 ||
          messages.any((message) => message.sequence > latest) ||
          messages.map((message) => message.sequence).toSet().length !=
              messages.length ||
          messages.map((message) => message.id).toSet().length !=
              messages.length) {
        throw const FormatException();
      }
      messages.sort((a, b) => a.sequence.compareTo(b.sequence));
      return RoomChatPage(messages, latest, data['hasOlder'] as bool);
    } on Object {
      throw const RoomChatFailure('invalidResponse');
    }
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
    final result = await _request('chatSend', {
      'roomId': roomId,
      'text': text,
      'attachment': ?attachment,
    });
    try {
      if (result['status'] != 'sent') throw const FormatException();
      return parseRoomChatMessage(result['message'] as Map);
    } on Object {
      throw const RoomChatFailure('outcomeUnknown');
    }
  }
}

RoomChatMessage parseRoomChatMessage(Map value) {
  String text(String key, {int maximum = 4096}) {
    final result = value[key] as String;
    if (result.length > maximum) throw const FormatException();
    return result;
  }

  final id = text('messageId'), sequence = value['sequence'] as int;
  if (id.isEmpty || sequence <= 0) throw const FormatException();
  final attachment = value['attachment'] == null
      ? null
      : Map<String, Object?>.from(value['attachment'] as Map);
  final invitation = attachment?['kind'] != 'fleet_invitation'
      ? null
      : CommunityInvitationAttachment.parse({
          'title': attachment!['title'],
          'summary': attachment['summary'],
          'inviteCode': attachment['fleetInviteCode'],
          'expiresAt': attachment['expiresAt'],
        });
  return RoomChatMessage(
    sequence: sequence,
    id: id,
    kind: text('kind'),
    isSelf: value['isSelf'] == true && value['kind'] == 'player',
    avatar: inlineAvatar(value['avatarImageData']),
    userRef: value['userRef'] as String?,
    gameId: value['senderGameId'] as String? ?? '',
    sender: roomPersonName(text('senderCallsign'), text('senderGameId')),
    text: text('text'),
    time: DateTime.parse(text('createdAt')),
    attachment: attachment == null ? null : Map.unmodifiable(attachment),
    communityInvitation: invitation,
  );
}
