abstract interface class PrivacyPublicationPort {
  bool get publicationSupported;
  Future<PrivacyPublicationView> publication(String action, {int? revision});
}

class PrivacyPublicationView {
  const PrivacyPublicationView(
    this.state, {
    this.revision,
    this.firstUseRequired,
    this.errorCode,
  });
  final String state;
  final int? revision;
  final String? errorCode;
  // Unknown/older Hosts cannot initiate an automatic consent prompt.
  final bool? firstUseRequired;
}
