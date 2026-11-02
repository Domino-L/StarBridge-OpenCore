import 'package:flutter/foundation.dart';

import 'official_runtime_privacy_module.dart';
import 'official_runtime_privacy_port.dart';

/// The main-fleet audience's read-outs and draft edits on the local privacy
/// editor. Saving and publication stay with the controller.
mixin LocalPrivacyOfficialEdits on ChangeNotifier {
  @protected
  OfficialRuntimePrivacyModule get officialModule;
  bool get canEdit;

  OfficialRuntimePrivacySnapshot? get officialScope => officialModule.scope;
  int? get officialDraftFields => officialModule.draftFields;
  int? get officialDraftAudience => officialModule.draftAudience;
  bool get officialCancelSavedScope => officialModule.cancelSavedScope;
  bool get officialScopeFailed => officialModule.failed;
  bool get officialScopeReading => officialModule.reading;
  OfficialPrivacySaveStage get officialSaveStage => officialModule.stage;
  bool get officialRuntimePrivacySupported => officialModule.supported;
  bool get officialDirty => officialModule.dirty;
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

  void chooseCancelSavedOfficialScope() {
    if (!canCancelOfficial) return;
    officialModule.chooseCancel();
    notifyListeners();
  }
}
