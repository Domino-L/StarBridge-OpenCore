abstract interface class CommunityInvitePort {
  Stream<void> get invalidations;
  Future<CommunityInvitePreview> previewInvite(String inviteCode);
  Future<CommunityInviteOutcome> acceptInvite(
    String requestId,
    String previewRef,
  );
}

final class CommunityInvitePreview {
  const CommunityInvitePreview({
    required this.previewRef,
    required this.name,
    required this.code,
    required this.commander,
    required this.memberCount,
    required this.joinPolicy,
    required this.expiresAt,
    required this.remainingUses,
    required this.alreadyMember,
    this.membershipConflict = false,
  });
  final String previewRef, name, code, commander, joinPolicy;
  final int memberCount, remainingUses;
  final DateTime? expiresAt;
  final bool alreadyMember;
  final bool membershipConflict;

  factory CommunityInvitePreview.parse(Map<String, Object?> value) {
    String text(String key, int max) {
      final field = value[key];
      if (field is! String ||
          field.length > max ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(field)) {
        throw const FormatException();
      }
      return field;
    }

    int number(String key, int min) {
      final field = value[key];
      if (field is! int || field < min || field > 2147483647) {
        throw const FormatException();
      }
      return field;
    }

    final reference = text('previewRef', 32);
    final name = text('name', 512), code = text('code', 256);
    final expiry = value['expiresAt'];
    DateTime? parsedExpiry;
    if (expiry != null) {
      if (expiry is! String ||
          expiry.length > 64 ||
          (parsedExpiry = DateTime.tryParse(expiry)) == null) {
        throw const FormatException();
      }
    }
    if (value['schemaVersion'] != 1 ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(reference) ||
        name.isEmpty ||
        code.isEmpty ||
        value['alreadyMember'] is! bool ||
        value.containsKey('membershipConflict') &&
            value['membershipConflict'] is! bool ||
        value['acceptMode'] != 'direct') {
      throw const FormatException();
    }
    return CommunityInvitePreview(
      previewRef: reference,
      name: name,
      code: code,
      commander: text('commander', 512),
      memberCount: number('memberCount', 0),
      joinPolicy: text('joinPolicy', 32),
      expiresAt: parsedExpiry,
      remainingUses: number('remainingUses', -1),
      alreadyMember: value['alreadyMember'] as bool,
      membershipConflict: value['membershipConflict'] as bool? ?? false,
    );
  }
}

final class CommunityInviteOutcome {
  const CommunityInviteOutcome(this.status, {this.error});
  final String status;
  final String? error;
  factory CommunityInviteOutcome.parse(Map<String, Object?> value) {
    final status = value['status'], error = value['error'];
    if (value['schemaVersion'] != 1 ||
        !const {'accepted', 'rejected', 'unknown'}.contains(status) ||
        error != null &&
            !const {
              'busy',
              'refreshRequired',
              'requestChanged',
              'inviteInvalid',
              'identityUnavailable',
              'notAllowed',
              'membershipConflict',
              'outcomeUnknown',
              'unavailable',
            }.contains(error)) {
      throw const FormatException();
    }
    return CommunityInviteOutcome(status as String, error: error as String?);
  }
}
