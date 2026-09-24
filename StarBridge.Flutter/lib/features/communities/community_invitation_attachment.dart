/// Historical display metadata, never proof that an invitation can be used.
/// Opening this card must resolve the code through CommunityInvitePort again.
final class CommunityInvitationAttachment {
  const CommunityInvitationAttachment({
    required this.title,
    required this.summary,
    required this.inviteCode,
    this.expiresAt,
  });
  final String title, summary, inviteCode;
  final DateTime? expiresAt;

  factory CommunityInvitationAttachment.parse(Map value) {
    String text(String key, int max) {
      final field = value[key];
      if (field is! String ||
          field.trim().isEmpty ||
          field.length > max ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(field)) {
        throw const FormatException();
      }
      return field;
    }

    final code = text('inviteCode', 40);
    final expiry = value['expiresAt'];
    if (code.trim().length < 6 ||
        (expiry != null &&
            (expiry is! String ||
                expiry.length > 64 ||
                DateTime.tryParse(expiry) == null))) {
      throw const FormatException();
    }
    return CommunityInvitationAttachment(
      title: text('title', 64),
      summary: text('summary', 240),
      inviteCode: code,
      expiresAt: expiry == null ? null : DateTime.parse(expiry as String),
    );
  }
}
