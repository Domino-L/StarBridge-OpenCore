import 'personal_profile_models.dart';

class ProfileVisibilityState {
  const ProfileVisibilityState(this.revision, this.visibility);
  final int revision;
  final PersonalProfileVisibility visibility;
}

abstract interface class ProfileVisibilityAccess {
  Future<ProfileVisibilityState> readVisibility();
  Future<ProfileVisibilityState> saveVisibility(
    ProfileVisibilityState expected,
    PersonalProfileVisibility visibility,
  );
}
