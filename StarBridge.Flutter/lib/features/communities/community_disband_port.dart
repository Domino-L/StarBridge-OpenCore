abstract interface class CommunityDisbandPort {
  Stream<void> get invalidations;
  bool get disbandAvailable;
  Future<CommunityDisbandPreview> readDisband(String targetRef);
  Future<CommunityDisbandOutcome> disband(
    String targetRef,
    String confirmationRef,
    String password,
  );
}

final class CommunityDisbandPreview {
  const CommunityDisbandPreview(
    this.targetRef,
    this.confirmationRef,
    this.name,
    this.memberCount,
    this.canDisband, {
    this.isExample = false,
  });
  final String targetRef, confirmationRef, name;
  final int memberCount;
  final bool canDisband, isExample;
  factory CommunityDisbandPreview.parse(Map<String, Object?> value) {
    bool reference(Object? v) =>
        v is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(v);
    final name = value['name'], count = value['memberCount'];
    if (value['schemaVersion'] != 1 ||
        value['credentialMode'] != 'legacyPassword' ||
        !reference(value['targetRef']) ||
        !reference(value['confirmationRef']) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 512 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
        count is! int ||
        count < 0 ||
        count > 100000 ||
        value['canDisband'] is! bool) {
      throw const FormatException();
    }
    return CommunityDisbandPreview(
      value['targetRef'] as String,
      value['confirmationRef'] as String,
      name,
      count,
      value['canDisband'] as bool,
    );
  }
}

final class CommunityDisbandOutcome {
  const CommunityDisbandOutcome(this.status, {this.error});
  final String status;
  final String? error;
  factory CommunityDisbandOutcome.parse(Map<String, Object?> value) {
    final status = value['status'], error = value['error'];
    if (value['schemaVersion'] != 1 ||
        !{'accepted', 'rejected', 'unknown'}.contains(status) ||
        status == 'accepted' && error != null ||
        status == 'unknown' && error != 'outcomeUnknown' ||
        status == 'rejected' &&
            !{
              'busy',
              'passwordInvalid',
              'identityUnavailable',
              'notAllowed',
              'refreshRequired',
              'unavailable',
            }.contains(error)) {
      throw const FormatException();
    }
    return CommunityDisbandOutcome(status as String, error: error as String?);
  }
}
