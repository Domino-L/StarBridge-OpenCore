import 'dart:convert';

import 'local_privacy_controller.dart';
import 'local_privacy_read_helpers.dart';

/// One organization's own page: its save and discard leave every other pending
/// privacy edit alone. [code] is null for the main fleet.
extension LocalPrivacyScopedSave on LocalPrivacyController {
  bool organizationDirty(String? code) {
    if (code == null) return officialDirty;
    if (!hasSaved) return dirty;
    final edited = privacyScopeIn(draft, code),
        saved = privacyScopeIn(savedSettings, code);
    return jsonEncode(edited?.toJson()) != jsonEncode(saved?.toJson());
  }

  /// Main-fleet saves always require an edit in that scope. A community may
  /// reapply its saved choice without submitting other pending edits.
  bool canSaveOrganization(String? code) =>
      canSave &&
      (code == null
          ? officialSubmitRequired
          : !hasSaved || !dirty || organizationDirty(code));

  Future<bool> saveOrganization(String? code) => code != null
      ? save(onlyCommunity: code)
      : officialSubmitRequired
      ? save(officialOnly: true, keepDraft: true)
      : Future.value(false);

  void discardOrganization(String? code) {
    if (saving || publicationBusy) return;
    if (code == null) return discardOfficial();
    final current = draft;
    if (current == null || !hasSaved) return discard();
    edit(
      current.copyWith(
        communities: privacyScopesReplacing(
          current.communities,
          code,
          privacyScopeIn(savedSettings, code),
        ),
      ),
    );
  }
}
