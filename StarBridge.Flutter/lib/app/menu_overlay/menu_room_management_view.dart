import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/room_commands.dart';
import '../../features/party_rooms/room_invitations.dart';

/// Display aliases only; actual service identifiers stay in the primary engine.
final class MenuRoomManagementView {
  MenuRoomManagementView(Map raw) {
    current = raw['current'] == true;
    String text(Map row, String key, [int limit = 512]) {
      final value = row[key];
      if (value is! String || value.length > limit) {
        throw const FormatException();
      }
      return value;
    }

    String alias(Map row, String key) {
      final value = text(row, key, 32);
      if (!RegExp(r'^m[1-9][0-9]{0,12}$').hasMatch(value)) {
        throw const FormatException();
      }
      return value;
    }

    currentRoomAlias = alias(raw, 'currentRoomAlias');

    List<Map> list(String key) {
      final value = raw[key] ?? const [];
      if (value is! List || value.length > 256 || value.any((e) => e is! Map)) {
        throw const FormatException();
      }
      return value.cast<Map>();
    }

    final grant = raw['actions'];
    if (grant is! Map) throw const FormatException();
    for (final e in grant.entries) {
      if (!operations.any((op) => op.name == e.key) ||
          e.value is! String ||
          !RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(e.value)) {
        throw const FormatException();
      }
      actions[e.key as String] = e.value as String;
    }
    applications = [
      for (final row in list('applications'))
        RoomApplication(
          id: alias(row, 'id'),
          callsign: text(row, 'name'),
          gameId: '',
          createdAt: DateTime.parse(text(row, 'time', 64)),
        ),
    ];
    List<RoomInvitation> invitations(String key) => [
      for (final row in list(key))
        RoomInvitation(
          id: alias(row, 'id'),
          roomId: alias(row, 'room'),
          title: text(row, 'title'),
          inviter: text(row, 'inviter'),
          recipient: text(row, 'recipient'),
          expiresAt: DateTime.parse(text(row, 'expires', 64)),
        ),
    ];
    received = invitations('received');
    sent = invitations('sent');
    final response = raw['reply'];
    if (response != null) {
      if (response is! Map ||
          response['request'] is! String ||
          !RegExp(r'^q[1-9][0-9]{0,13}$').hasMatch(response['request'])) {
        throw const FormatException();
      }
      request = response['request'] as String;
      if (!const {
        'closed',
        'approved',
        'declined',
        'targets',
        'invited',
        'revoked',
        'rejected',
        'stale',
        'unknown',
      }.contains(response['status'])) {
        throw const FormatException();
      }
      final targets = response['targets'] ?? const [];
      if (targets is! List || targets.length > 256) {
        throw const FormatException();
      }
      reply = RoomCommandResult(
        text(response, 'status', 32),
        error: response['error'] == null ? null : text(response, 'error', 128),
        targets: [
          for (final row in targets)
            RoomInviteTarget(
              alias(row as Map, 'id'),
              text(row, 'name'),
              alreadyInvited: row['invited'] == true,
            ),
        ],
      );
    }
  }
  static const operations = [
    RoomOperation.close,
    RoomOperation.decide,
    RoomOperation.inviteTargets,
    RoomOperation.invite,
    RoomOperation.inviteDecline,
    RoomOperation.inviteRevoke,
  ];
  final actions = <String, String>{};
  late final bool current;
  late final String currentRoomAlias;
  late final List<RoomApplication> applications;
  late final List<RoomInvitation> received, sent;
  String? request;
  RoomCommandResult? reply;
}
