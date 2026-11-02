import 'personal_profile_models.dart';

class ProfileVisibilityState {
  const ProfileVisibilityState(
    this.revision,
    this.visibility, {
    this.availableVisibilities = legacyVisibilities,
  });
  static const legacyVisibilities = [
    PersonalProfileVisibility.everyone,
    PersonalProfileVisibility.friendsFleetAndOrganizations,
    PersonalProfileVisibility.friendsOnly,
    PersonalProfileVisibility.onlyMe,
  ];
  final int revision;
  final PersonalProfileVisibility visibility;
  final List<PersonalProfileVisibility> availableVisibilities;
}

abstract interface class ProfileVisibilityAccess {
  Future<ProfileVisibilityState> readVisibility();
  Future<ProfileVisibilityState> saveVisibility(
    ProfileVisibilityState expected,
    PersonalProfileVisibility visibility,
  );
}
