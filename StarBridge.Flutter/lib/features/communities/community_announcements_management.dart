import 'community_announcements_controller.dart';

extension CommunityAnnouncementsManagement on CommunityAnnouncementsController {
  /// Reads the editor outside the dialog unless it is current or was refused.
  /// Passing failures retry on the next verified open.
  Future<void> prepareManagementIfNeeded() async {
    final session = management;
    if (session == null || !session.port.managementAvailable) return;
    if (session.error == 'notAllowed' || editorAligned) return;
    if (session.editor != null && page == null) return;
    await prepareManagement();
  }

  /// The relay's current answer on managing announcements: an earlier refusal
  /// is not remembered past it, and a lost right takes the editor away.
  Future<void> recheckManagement({required bool allowed}) async {
    final session = management;
    if (session == null || !session.port.managementAvailable || !active) return;
    answerManagement(allowed);
    if (allowed && page == null) await enter();
    if (allowed ? !editorAligned : session.editor != null) {
      await prepareManagement();
    }
  }
}
