import 'personal_profile_models.dart';

/// Unsaved values only. The original module retains its live editing lease.
final class PersonalProfileEditorDraft {
  const PersonalProfileEditorDraft(
    this.edit, {
    this.requiresReload = false,
    this.validationError = false,
  });
  final PersonalProfileEdit edit;
  final bool requiresReload, validationError;
}

abstract interface class PersonalProfileDraftSession {
  bool get editingLeaseActive;
  bool get draftRequiresReload;
  bool keepEditorDraft(PersonalProfileEditorDraft draft);
  PersonalProfileEditorDraft? takeEditorDraft();
}
