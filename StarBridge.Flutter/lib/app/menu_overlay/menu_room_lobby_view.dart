import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/bridge_party_rooms_adapter.dart';
import '../../features/party_rooms/room_commands.dart';
import '../../features/party_rooms/room_invitations.dart';

final class MenuRoomLobbyView {
  const MenuRoomLobbyView(
    this.directory,
    this.actions,
    this.reply, {
    this.busy = false,
    this.rejectedAction,
    this.invitationReply,
  });
  final bool busy;
  final String? rejectedAction;
  final Map<String, Object?>? invitationReply;
  final RoomDirectory directory;
  final Map<RoomOperation, String> actions;
  final Map<String, Object?>? reply;
  static RoomDirectory readDirectory(Object? value) {
    if (value is! Map) throw const FormatException();
    final rows = value['rooms'];
    if (rows is! List || rows.length > 500) throw const FormatException();
    for (final room in rows) {
      if (room is! Map ||
          room['roomId'] is! String ||
          !RegExp(r'^r[1-9][0-9]{0,13}$').hasMatch(room['roomId'] as String) ||
          room['viewerIsHost'] == true ||
          room['pendingApplications'] != null) {
        throw const FormatException();
      }
      for (final member in room['members'] as List) {
        if (member is! Map ||
            member.containsKey('userRef') ||
            member.containsKey('removalToken')) {
          throw const FormatException();
        }
        final avatar = member['avatarImageData'];
        if (avatar != null &&
            (avatar is! String ||
                avatar.length > 28000 ||
                !avatar.startsWith('data:image/png;base64,'))) {
          throw const FormatException();
        }
      }
    }
    if (value['currentRoomId'] != null ||
        value['receivedInvitations'] != null ||
        value['sentInvitations'] != null) {
      throw const FormatException();
    }
    return parseRoomDirectory(Map<String, Object?>.from(value));
  }

  static MenuRoomLobbyView parse(
    Object? raw, {
    bool busy = false,
    String? rejectedAction,
  }) {
    if (raw is! Map) throw const FormatException();
    final actions = <RoomOperation, String>{};
    final source = raw['actions'];
    if (source is! Map) throw const FormatException();
    for (final op in [
      RoomOperation.create,
      RoomOperation.resolve,
      RoomOperation.join,
      RoomOperation.invitePreview,
      RoomOperation.inviteJoin,
      RoomOperation.inviteDecline,
    ]) {
      final key = source[op.name];
      if (key == null) continue;
      if (key is! String || !RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(key)) {
        throw const FormatException();
      }
      actions[op] = key;
    }
    final reply = raw['reply'];
    if (reply != null &&
        (reply is! Map ||
            reply['request'] is! String ||
            !RegExp(r'^q[1-9][0-9]{0,13}$')
                .hasMatch(reply['request'] as String) ||
            reply['status'] is! String ||
            (reply['status'] as String).length > 64 ||
            (reply['error'] != null &&
                (reply['error'] is! String ||
                    (reply['error'] as String).length > 128)))) {
      throw const FormatException();
    }
    if (reply is Map &&
        reply['preview'] != null &&
        readDirectory(reply['preview']).rooms.length != 1) {
      throw const FormatException();
    }
    final sourceDirectory = readDirectory(raw['directory']);
    final invitations = raw['invitations'] ?? const [];
    if (invitations is! List || invitations.length > 256) {
      throw const FormatException();
    }
    String text(Map row, String key, [int limit = 512]) {
      final value = row[key];
      if (value is! String || value.length > limit) {
        throw const FormatException();
      }
      return value;
    }

    final received = <RoomInvitation>[];
    final seen = <String>{};
    for (final row in invitations) {
      if (row is! Map) throw const FormatException();
      final id = text(row, 'id', 32), room = text(row, 'room', 32);
      if (!RegExp(r'^i[1-9][0-9]{0,13}$').hasMatch(id) ||
          !seen.add(id) ||
          !RegExp(r'^r[1-9][0-9]{0,13}$').hasMatch(room)) {
        throw const FormatException();
      }
      received.add(
        RoomInvitation(
          id: id,
          roomId: room,
          title: text(row, 'title'),
          inviter: text(row, 'inviter'),
          recipient: text(row, 'recipient'),
          expiresAt: DateTime.parse(text(row, 'expires', 64)),
        ),
      );
    }
    final invitationReply = raw['invitationReply'];
    if (invitationReply != null) {
      if (invitationReply is! Map ||
          invitationReply['request'] is! String ||
          !RegExp(r'^q[1-9][0-9]{0,13}$')
              .hasMatch(invitationReply['request']) ||
          !const {
            'resolved',
            'joined',
            'declined',
            'rejected',
            'stale',
            'unknown',
          }.contains(invitationReply['status'])) {
        throw const FormatException();
      }
      if (invitationReply['error'] != null) text(invitationReply, 'error', 128);
      if (invitationReply['preview'] != null &&
          readDirectory(invitationReply['preview']).rooms.length != 1) {
        throw const FormatException();
      }
    }
    return MenuRoomLobbyView(
      RoomDirectory(
        rooms: sourceDirectory.rooms,
        serverTime: sourceDirectory.serverTime,
        tagOptions: sourceDirectory.tagOptions,
        viewerPendingRoomIds: sourceDirectory.viewerPendingRoomIds,
        receivedInvitations: received,
      ),
      actions,
      reply == null ? null : Map<String, Object?>.from(reply as Map),
      busy: busy,
      rejectedAction: rejectedAction,
      invitationReply: invitationReply == null
          ? null
          : Map<String, Object?>.from(invitationReply as Map),
    );
  }
}
