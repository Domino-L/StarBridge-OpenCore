final class RoomInvitation {
  const RoomInvitation({
    required this.id,
    required this.roomId,
    required this.title,
    required this.inviter,
    required this.recipient,
    required this.expiresAt,
  });
  final String id, roomId, title, inviter, recipient;
  final DateTime expiresAt;
}

final class RoomInviteTarget {
  const RoomInviteTarget(
    this.reference,
    this.name, {
    this.alreadyInvited = false,
  });
  final String reference, name;
  final bool alreadyInvited;
}

abstract interface class RoomInvitationsPort {
  bool get supportsInvitations;
}

String roomPersonName(String callsign, String handle) => callsign.isEmpty
    ? handle
    : handle.isEmpty
    ? callsign
    : '$callsign ($handle)';
List<RoomInvitation> parseInvitations(Object? raw) {
  if (raw == null) return const [];
  final list = raw as List;
  if (list.length > 256) throw const FormatException();
  final seen = <String>{};
  String text(Map item, String key) {
    final value = item[key] as String;
    if (value.length > 4096) throw const FormatException();
    return value;
  }

  return list.map((value) {
    final item = value as Map;
    final id = text(item, 'invitationId');
    if (id.isEmpty || !seen.add(id)) throw const FormatException();
    return RoomInvitation(
      id: id,
      roomId: text(item, 'roomId'),
      title: text(item, 'roomTitle'),
      inviter: roomPersonName(
        text(item, 'inviterCallsign'),
        text(item, 'inviterGameId'),
      ),
      recipient: roomPersonName(
        text(item, 'recipientCallsign'),
        text(item, 'recipientGameId'),
      ),
      expiresAt: DateTime.parse(item['expiresAt'] as String),
    );
  }).toList();
}
