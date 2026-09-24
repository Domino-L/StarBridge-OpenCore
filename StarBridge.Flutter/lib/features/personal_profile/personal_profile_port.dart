import 'personal_profile_models.dart';

abstract interface class PersonalProfilePort {
  Stream<void> get invalidations;

  Future<PersonalProfileSnapshot> read();
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit);
  Future<void> close();
}
