abstract interface class CommunityAnnouncementWritePort {
  bool get announcementWritesAvailable;
  Future<CommunityAnnouncementOutcome> manageAnnouncement(
    CommunityAnnouncementIntent intent,
  );
}

final class CommunityAnnouncementIntent {
  CommunityAnnouncementIntent({
    required this.targetRef,
    required this.requestId,
    required this.action,
    this.announcementRef,
    String? title,
    String? content,
  }) : title = title?.trim(),
       content = content
           ?.replaceAll('\r\n', '\n')
           .replaceAll('\r', '\n')
           .trim() {
    if (!_reference.hasMatch(targetRef) ||
        !_reference.hasMatch(requestId) ||
        !['publish', 'edit', 'withdraw'].contains(action) ||
        action == 'publish' && announcementRef != null ||
        action != 'publish' &&
            (announcementRef == null ||
                !_reference.hasMatch(announcementRef!))) {
      throw const FormatException();
    }
    if (action == 'withdraw') {
      if (title != null || content != null) throw const FormatException();
    } else if (title == null ||
        content == null ||
        this.title!.isEmpty ||
        title.length > 48 ||
        content.length > 1200 ||
        RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(title) ||
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]').hasMatch(content)) {
      throw const FormatException();
    }
  }
  static final _reference = RegExp(r'^[a-f0-9]{32}$');
  final String targetRef, requestId, action;
  final String? announcementRef, title, content;
  Map<String, Object?> toPayload() => {
    'targetRef': targetRef,
    'requestId': requestId,
    'action': action,
    'announcementRef': announcementRef,
    if (action != 'withdraw') ...{'title': title, 'content': content},
  };
}

final class CommunityAnnouncementOutcome {
  const CommunityAnnouncementOutcome(this.status, {this.error, this.revision});
  factory CommunityAnnouncementOutcome.parse(
    Map<String, Object?> row,
    CommunityAnnouncementIntent intent,
  ) {
    final status = row['status'];
    final error = row['error'];
    final revision = row['revision'];
    if (row['schemaVersion'] != 1 ||
        row['targetRef'] != intent.targetRef ||
        row['requestId'] != intent.requestId ||
        row['action'] != intent.action ||
        !['accepted', 'rejected', 'unknown'].contains(status) ||
        error != null && (error is! String || error.length > 64)) {
      throw const FormatException();
    }
    if (status == 'accepted') {
      if (error != null || revision is! int || revision <= 0) {
        throw const FormatException();
      }
      return CommunityAnnouncementOutcome('accepted', revision: revision);
    }
    if (revision != null) throw const FormatException();
    return CommunityAnnouncementOutcome(
      status as String,
      error: error as String?,
    );
  }
  final String status;
  final String? error;
  final int? revision;
}
