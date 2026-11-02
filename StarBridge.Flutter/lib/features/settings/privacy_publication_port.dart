abstract interface class PrivacyPublicationPort {
  bool get publicationSupported;
  Future<PrivacyPublicationView> publication(String action, {int? revision});
}

/// Optional push of publication status changes. When supported, the status
/// is re-read on change and only a slow fallback timer remains.
abstract interface class PrivacyPublicationChangePort {
  bool get publicationEventsSupported;
  Stream<void> get publicationChanges;
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
