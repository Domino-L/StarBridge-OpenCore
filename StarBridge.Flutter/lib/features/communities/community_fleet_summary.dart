/// Read-only aggregate contract shared by the client and menu renderer.
/// No member identities, inventory references, or access capabilities.
abstract interface class CommunityFleetSummary {
  static const maximumShips = 10000;
  int get shipCount;
  int get modelCount;
  int get sharingMemberCount;
  int get pricedCount;
  int get totalCents;
  Map<String, int> get sizes;
  Map<String, int> get roles;
  int countAt(String size, String role);
}
