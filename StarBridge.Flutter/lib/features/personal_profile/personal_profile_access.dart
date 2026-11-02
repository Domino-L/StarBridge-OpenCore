import 'personal_profile_models.dart';
import 'personal_profile_visibility.dart';

/// Immediate UI admission; original module and Native lease remain the writers.
abstract interface class PersonalProfileAccess {
  bool get permitsEditing;
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit);
  ProfileVisibilityAccess get visibility;
}
