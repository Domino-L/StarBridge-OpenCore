import 'party_rooms_module.dart';
import 'room_invitations.dart';

enum RoomOperation {
  create,
  join,
  resolve,
  leave,
  update,
  close,
  decide,
  inviteTargets,
  invite,
  inviteJoin,
  invitePreview,
  inviteDecline,
  inviteRevoke,
}

final class RoomCommand {
  RoomCommand(this.operation, Map<String, Object?> data)
    : data = Map.unmodifiable(data);
  final RoomOperation operation;
  final Map<String, Object?> data;
}

final class RoomCommandResult {
  const RoomCommandResult(
    this.status, {
    this.error,
    this.directory,
    this.preview,
    this.targets = const [],
  });
  final String status;
  final String? error;
  final RoomDirectory? directory;
  final PartyRoom? preview;
  final List<RoomInviteTarget> targets;
  bool get accepted => const [
    'joined',
    'pending',
    'left',
    'closed',
    'resolved',
    'updated',
    'approved',
    'declined',
    'targets',
    'invited',
    'revoked',
  ].contains(status);
}

abstract interface class RoomCommandsPort {
  bool get supportsCommands;
  Future<RoomCommandResult> execute(RoomCommand command);
}

abstract interface class RoomManagementPort {
  bool get supportsManagement;
}
