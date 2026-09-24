abstract interface class CommunityAdmissionsPort {
  Stream<void> get invalidations;
  Future<CommunityAdmissionsPage> readAdmissions(
    String targetRef,
    String section,
    int offset,
  );
  Future<CommunityAdmissionOutcome> manageAdmissions(
    CommunityAdmissionIntent intent,
  );
}

enum CommunityAdmissionAction { approve, decline, generateInvite, revokeInvite }

/// One explicit user decision. Keep the request ID for retries of that decision.
final class CommunityAdmissionIntent {
  const CommunityAdmissionIntent({
    required this.requestId,
    required this.targetRef,
    required this.action,
    this.entryRef,
    this.expiresInDays,
    this.maxUses,
    this.confirmUncertainRetry = false,
  });
  final String requestId, targetRef;
  final CommunityAdmissionAction action;
  final String? entryRef;
  final int? expiresInDays, maxUses;
  // Set only after a separate warning/confirmation, never on an automatic retry.
  final bool confirmUncertainRetry;

  Map<String, Object?> toPayload() {
    final reference = RegExp(r'^[a-f0-9]{32}$');
    final generate = action == CommunityAdmissionAction.generateInvite;
    if (!reference.hasMatch(requestId) ||
        !reference.hasMatch(targetRef) ||
        (generate
            ? entryRef != null ||
                  expiresInDays == null ||
                  expiresInDays! < 1 ||
                  expiresInDays! > 30 ||
                  maxUses == null ||
                  maxUses! < 0 ||
                  maxUses! > 50
            : entryRef == null ||
                  !reference.hasMatch(entryRef!) ||
                  expiresInDays != null ||
                  maxUses != null)) {
      throw const FormatException('Invalid organization management intent');
    }
    return Map.unmodifiable({
      'requestId': requestId,
      'targetRef': targetRef,
      'action': action.name,
      if (entryRef != null) 'entryRef': entryRef,
      if (generate) 'expiresInDays': expiresInDays,
      if (generate) 'maxUses': maxUses,
      'confirmUncertainRetry': confirmUncertainRetry,
    });
  }
}

final class CommunityAdmissionOutcome {
  const CommunityAdmissionOutcome(this.status, {this.error});
  final String status;
  final String? error;
  factory CommunityAdmissionOutcome.parse(Map<String, Object?> value) {
    final status = value['status'], error = value['error'];
    if (value['schemaVersion'] != 1 ||
        !const {'accepted', 'rejected', 'unknown'}.contains(status) ||
        status == 'accepted' && error != null ||
        status == 'unknown' && error != 'outcomeUnknown' ||
        status == 'rejected' &&
            !const {
              'busy',
              'refreshRequired',
              'requestChanged',
              'identityUnavailable',
              'notAllowed',
              'unavailable',
              'dataInvalid',
              'notFound',
            }.contains(error)) {
      throw const FormatException('Invalid organization management outcome');
    }
    return CommunityAdmissionOutcome(status as String, error: error as String?);
  }
}

/// Validated, immutable management projection. Contains no account or server row IDs.
final class CommunityAdmissionsPage {
  CommunityAdmissionsPage._(
    this.targetRef,
    this.section,
    this.offset,
    this.next,
    this.totalCount,
    this.access,
    this.items,
    this.fetchedAt,
    this.currentInviteAvailable,
    this.currentInvite,
  );
  final String targetRef, section;
  final int offset, totalCount;
  final int? next;
  final Map<String, bool> access;
  final List<Map<String, Object?>> items;
  final DateTime fetchedAt;
  final bool currentInviteAvailable;
  final Map<String, Object?>? currentInvite;

  factory CommunityAdmissionsPage.parse(
    Map<String, Object?> value,
    String targetRef,
    String section,
    int offset,
  ) {
    Never invalid() =>
        throw const FormatException('Invalid organization management page');
    String text(Map row, String key, int max, {bool multiline = false}) {
      final v = row[key];
      if (v is! String ||
          v.length > max ||
          RegExp(
            multiline
                ? r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'
                : r'[\x00-\x1f\x7f]',
          ).hasMatch(v)) {
        invalid();
      }
      return v;
    }

    int number(Map row, String key, int max) {
      final v = row[key];
      if (v is! int || v < 0 || v > max) invalid();
      return v;
    }

    bool flag(Map row, String key) {
      final v = row[key];
      if (v is! bool) invalid();
      return v;
    }

    DateTime? date(Map row, String key) {
      if (row[key] == null) return null;
      final value = text(row, key, 64);
      return DateTime.tryParse(value) ?? invalid();
    }

    if (value['schemaVersion'] != 1 ||
        value['targetRef'] != targetRef ||
        value['section'] != section ||
        !const ['applications', 'invites'].contains(section) ||
        value['offset'] != offset ||
        offset < 0 ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(targetRef)) {
      invalid();
    }
    final total = number(value, 'totalCount', 1000000);
    final next = value['next'] == null ? null : number(value, 'next', 1000000);
    final raw = value['items'], rawAccess = value['access'];
    if (raw is! List ||
        rawAccess is! Map ||
        raw.length > 20 ||
        offset > total ||
        raw.length != (total - offset).clamp(0, 20) ||
        next != (offset + raw.length < total ? offset + raw.length : null)) {
      invalid();
    }
    final access = {
      for (final key in const [
        'canReadApplications',
        'canDecideApplications',
        'canReadInvites',
        'canCreateInvite',
        'canSendInvitationCard',
      ])
        key: flag(rawAccess, key),
    };
    if (!access[section == 'applications'
        ? 'canReadApplications'
        : 'canReadInvites']!) {
      invalid();
    }
    final seen = <String>{};
    final rows = <Map<String, Object?>>[];
    for (final row in raw) {
      if (row is! Map) invalid();
      final ref = text(row, 'entryRef', 32);
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(ref) || !seen.add(ref)) invalid();
      final status = text(row, 'status', 16);
      final projected = <String, Object?>{
        'entryRef': ref,
        'status': status,
        'createdAt': date(row, 'createdAt'),
      };
      if (section == 'applications') {
        if (status != 'Pending') invalid();
        projected.addAll({
          'gameName': text(row, 'gameName', 512),
          'callsign': text(row, 'callsign', 512),
          'message': text(row, 'message', 8192, multiline: true),
          'hasAvatar': flag(row, 'hasAvatar'),
        });
      } else {
        if (!const [
          'Active',
          'Revoked',
          'Expired',
          'Exhausted',
          'Unavailable',
        ].contains(status)) {
          invalid();
        }
        projected.addAll({
          'code': text(row, 'code', 128),
          'createdBy': text(row, 'createdBy', 512),
          'expiresAt': date(row, 'expiresAt'),
          'maxUses': number(row, 'maxUses', 2147483647),
          'usedCount': number(row, 'usedCount', 2147483647),
          'isOwn': flag(row, 'isOwn'),
          'canRevoke': flag(row, 'canRevoke'),
        });
      }
      rows.add(Map.unmodifiable(projected));
    }
    if (value.containsKey('currentInviteAvailable') &&
        value['currentInviteAvailable'] is! bool) {
      invalid();
    }
    final available = value['currentInviteAvailable'] == true;
    if (available && !value.containsKey('currentInvite')) invalid();
    Map<String, Object?>? currentInvite;
    final rawCurrent = value['currentInvite'];
    if (rawCurrent != null) {
      if (!available ||
          section != 'invites' ||
          rawCurrent is! Map ||
          total == 0) {
        invalid();
      }
      currentInvite = CommunityAdmissionsPage.parse(
        {
          ...value,
          'items': [rawCurrent],
          'offset': 0,
          'next': null,
          'totalCount': 1,
          'currentInvite': null,
          'currentInviteAvailable': false,
        },
        targetRef,
        section,
        0,
      ).items.single;
      if (currentInvite['isOwn'] != true ||
          currentInvite['status'] != 'Active') {
        invalid();
      }
      for (final row in rows.where(
        (row) => row['entryRef'] == currentInvite!['entryRef'],
      )) {
        if (row.keys.any((key) => row[key] != currentInvite![key])) invalid();
      }
    }
    return CommunityAdmissionsPage._(
      targetRef,
      section,
      offset,
      next,
      total,
      Map.unmodifiable(access),
      List.unmodifiable(rows),
      date(value, 'fetchedAt') ?? invalid(),
      available,
      currentInvite,
    );
  }
}
