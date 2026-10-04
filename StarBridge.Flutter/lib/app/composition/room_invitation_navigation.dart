import 'package:flutter/widgets.dart';

import '../../features/party_rooms/room_invitation_dialog.dart';
import 'app_composition.dart';

/// The shell guards navigation; composition coordinates the room feature.
Future<bool> openRoomInvitationDestination(
  BuildContext context,
  AppComposition composition,
  String route, {
  required bool Function() isCurrent,
}) async {
  final rooms = composition.partyRooms;
  final revision = rooms.contextRevision;
  if (!await rooms.refreshForNotification()) return false;
  if (!context.mounted || !isCurrent() || revision != rooms.contextRevision) {
    return true;
  }
  final invitationId = Uri.parse(route).queryParameters['invitation'];
  final sent =
      invitationId != null &&
      rooms.directory?.sentInvitations.any((item) => item.id == invitationId) ==
          true;
  await showRoomInvitations(
    context,
    rooms,
    host: sent,
    invitationId: invitationId,
  );
  return true;
}
