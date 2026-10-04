bool validRoomInvitationId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(value);

/// Navigation only: membership is re-read by the destination before any action.
bool isRoomInvitationDestination(String route) {
  final uri = Uri.tryParse(route);
  return uri != null &&
      !uri.hasScheme &&
      !uri.hasAuthority &&
      uri.path == '/rooms/invitations' &&
      !uri.hasFragment &&
      (uri.queryParametersAll.isEmpty ||
          uri.queryParametersAll.length == 1 &&
              uri.queryParametersAll['invitation']?.length == 1 &&
              validRoomInvitationId(uri.queryParameters['invitation']!));
}
