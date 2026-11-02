import 'official_fleet_members_models.dart';

abstract interface class OfficialFleetMembersPort {
  Stream<void> get invalidations;

  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  );

  Future<void> close();
}

/// Optional reads owned by the existing activity scheduler, never a page timer.
abstract interface class OfficialFleetMembersActivityPort {
  Stream<void> get runtimeChanges;
  Stream<void> get runtimeScopeInvalidations;
  void retireRuntimeActivity();
}
