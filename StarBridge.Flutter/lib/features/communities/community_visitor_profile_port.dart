import '../personal_profile/personal_profile_models.dart';

abstract interface class CommunityVisitorProfilePort {
  Stream<void> get invalidations;
  bool get visitorProfilesAvailable;
  Future<PersonalProfileSnapshot> readMemberPersonalProfile(
    String targetRef,
    String memberRef,
  );
}
