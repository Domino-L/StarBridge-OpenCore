import 'dart:async';

import 'package:flutter/foundation.dart';

import 'official_runtime_privacy_module.dart';
import 'official_runtime_privacy_port.dart';
import 'privacy_publication_port.dart';

/// The main-fleet audience's read-outs and draft edits on the local privacy
/// editor. Saving and publication stay with the controller.
mixin LocalPrivacyOfficialEdits on ChangeNotifier {
  @protected
  OfficialRuntimePrivacyModule get officialModule;
  bool get canEdit;

  /// Whether a settings read has succeeded. Before the first one, an account
  /// error at startup usually means the account is still settling: the page
  /// shows a wait and the periodic full read (draft-less, not ready) retries.
  bool get hasReadOnce => _hasReadOnce;
  set hasReadOnce(bool value) {
    _hasReadOnce = value;
    if (value) stopAccountWait();
  }

  /// Leaving the page stops the wait; reopening before a read starts it anew.
  @protected
  void stopAccountWait() {
    _accountWait?.cancel();
    _accountWait = null;
  }

  bool _hasReadOnce = false;

  /// The startup wait is bounded: a genuinely signed-out first launch also
  /// answers account_changed, so after this the page shows the sign-in prompt.
  /// The periodic full read keeps retrying and still recovers by itself.
  static const accountWaitLimit = Duration(seconds: 45);
  Timer? _accountWait;
  bool _accountWaitExpired = false;

  /// Whether a signed-out page with no settings yet still shows the wait.
  bool get accountWaitShown {
    if (hasReadOnce || _accountWaitExpired) return false;
    _accountWait ??= Timer(accountWaitLimit, () {
      _accountWaitExpired = true;
      notifyListeners();
    });
    return true;
  }

  @override
  void dispose() {
    _accountWait?.cancel();
    super.dispose();
  }
  PrivacyPublicationView get publicationView;

  OfficialRuntimePrivacySnapshot? get officialScope => officialModule.scope;
  int? get officialDraftFields => officialModule.draftFields;
  int? get officialDraftAudience => officialModule.draftAudience;
  bool get officialCancelSavedScope => officialModule.cancelSavedScope;
  bool get officialScopeFailed => officialModule.failed;
  bool get officialScopeReading => officialModule.reading;
  OfficialPrivacySaveStage get officialSaveStage => officialModule.stage;
  bool get officialRuntimePrivacySupported => officialModule.supported;
  bool get officialDirty => officialModule.dirty;

  /// A save submits the main fleet choice for an edit or a reconfirmation.
  bool get officialSubmitRequired => officialDirty || officialReconfirmRequired;

  /// The relay refused this computer's main fleet choice as out of date
  /// (official_fleet.choice_changed). Saving the same choice again is the
  /// user's explicit confirmation; it is submitted with the server's current
  /// revision and a new operation. Never inferred without that save.
  /// This is not an unsaved edit: it never makes the editor dirty (no leave
  /// prompts, no paused refresh); it only enables and drives the save.
  bool get officialReconfirmRequired {
    final scope = officialModule.scope;
    return publicationView.errorCode == 'official_fleet.choice_changed' &&
        scope != null &&
        scope.savedForCurrentSource &&
        scope.canSave &&
        !officialModule.cancelSavedScope &&
        officialModule.draftFields != null;
  }
  bool get canEditOfficial => canEdit && officialModule.canEdit;
  bool get canCancelOfficial => canEdit && officialModule.canCancel;

  void editOfficialFields(int fields) {
    if (!canEditOfficial || fields < 0 || fields > 15) return;
    officialModule.edit(fields);
    notifyListeners();
  }

  /// Null is every current member; see [OfficialFleetAudience].
  void editOfficialAudience(int? maximumRankValue) {
    if (!canEditOfficial) return;
    officialModule.editAudience(maximumRankValue);
    notifyListeners();
  }

  void discardOfficial() {
    officialModule.discard();
    notifyListeners();
  }

  void chooseCancelSavedOfficialScope() {
    if (!canCancelOfficial) return;
    officialModule.chooseCancel();
    notifyListeners();
  }
}
