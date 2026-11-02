/// Presentation capability; a display identity does not grant a social target.
abstract interface class OrganizationMemberActions {
  bool get memberActionsAvailable;
}

bool organizationMemberActionsAvailable(Object port) =>
    port is! OrganizationMemberActions || port.memberActionsAvailable;
