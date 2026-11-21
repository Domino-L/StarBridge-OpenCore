abstract interface class PrivacyPublicationPort {
  bool get publicationSupported;
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
    bool firstOfficialDefault = false,
  });
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

  /// Ordinary organization saves can only reapply an existing sharing choice.
  bool allowsOrganizationApply({bool firstDefault = false}) =>
      !const {'withdrawn', 'withdrawalPending'}.contains(state) &&
      (firstDefault &&
              (firstUseRequired == true ||
                  errorCode == 'privacy_publication.consent_required') ||
          firstUseRequired != true &&
              errorCode != 'privacy_publication.consent_required' &&
              (firstUseRequired == false || state != 'inactive'));

  bool confirmsSharing(int expectedRevision) =>
      state == 'applied' && revision == expectedRevision && errorCode == null;
}
