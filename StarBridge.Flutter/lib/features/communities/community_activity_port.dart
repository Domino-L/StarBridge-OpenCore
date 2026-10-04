/// Content-free, account-bound invalidation hints. Reads still authorize data.
abstract interface class CommunityActivityPort {
  Stream<void> get workspaceChanges;
  bool get activityHealthy;
}
