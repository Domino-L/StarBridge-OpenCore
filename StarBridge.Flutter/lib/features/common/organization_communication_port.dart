import '../communities/community_announcements_port.dart';
import '../communities/community_chat_port.dart';
import '../communities/community_chat_send_port.dart';

export '../communities/community_announcements_port.dart';
export '../communities/community_chat_port.dart';
export '../communities/community_chat_send_port.dart';

/// A verified organization conversation using the existing collaboration wire
/// models. Management, invitations and community membership are separate ports.
abstract interface class OrganizationCommunicationPort
    implements
        CommunityAnnouncementsPort,
        CommunityChatPort,
        CommunityChatSendPort {
  Future<OrganizationCommunicationContext> open();
  Future<void> close();
}

final class OrganizationCommunicationContext {
  const OrganizationCommunicationContext(this.targetRef, this.name);
  final String targetRef, name;
}

typedef OrganizationCommunicationFactory =
    OrganizationCommunicationPort Function(String sourceRef);

/// Transport admission only. A reconnect must revalidate the organization;
/// neither online mode nor a wakeup grants membership or write authority.
abstract interface class OrganizationCommunicationConnectionPort {
  Stream<void> get connectionChanges;
  bool get onlineTrafficAllowed;
}
