import 'personal_profile_models.dart';
import 'personal_profile_public_header.dart';
import 'personal_profile_presentation.dart';

abstract interface class PersonalProfilePresentationWriter {
  Future<PersonalProfileActionResult> savePresentation(
    PersonalProfilePresentation expected,
    Map<String, Map<String, Object?>> edits,
  );
}

abstract interface class PersonalProfilePort {
  /// Hard loss of reading ownership. Old content and editing must end.
  Stream<void> get invalidations;

  Future<PersonalProfileSnapshot> read();
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit);
  Future<void> close();
}

/// Same-owner display changes. These do not revoke a currently open editor.
abstract interface class PersonalProfileContentChanges {
  Stream<void> get changes;
}

/// Optional owner read. A port without it remains compatible with older Hosts.
abstract interface class PersonalProfileAccountFactsReader {
  Future<PersonalProfilePublicFacts?> readAccountFacts();
}

/// A read-only owner surface can show the local fallback while import runs.
abstract interface class PersonalProfileDisplayReader {
  Future<PersonalProfileSnapshot> readForDisplay();
}
