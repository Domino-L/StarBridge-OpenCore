import '../common/organization_hangar_sharing.dart';
import 'community_hangar_sharing_port.dart';

/// Preserve the existing community contract and its64 organization limit. This
/// adapter never converts organization target refs into ship-instance refs.
final class CommunityOrganizationSharingAdapter
    implements OrganizationHangarSharingPort {
  CommunityOrganizationSharingAdapter(this.port);
  final CommunityHangarSharingPort port;
  @override
  Stream<void> get invalidations => port.invalidations;
  @override
  bool get available => port.hangarSharingAvailable;
  @override
  Future<OrganizationSharingDraft> read(
    String? sourceRef, {
    String? scopeRef,
  }) async {
    final value = await port.readHangarSharing();
    final selected = value.options
        .where((entry) => entry.selected)
        .map((entry) => entry.targetRef)
        .toList();
    return OrganizationSharingDraft(
      mode: OrganizationSharingMode.audiences,
      editRef: value.editRef,
      state: 'available',
      page: OrganizationSharingPage(
        value.editRef,
        0,
        value.options.length,
        null,
        value.options
            .map(
              (entry) => OrganizationSharingOption(entry.targetRef, entry.name),
            )
            .toList(),
      ),
      selectedRefs: selected,
      selectedCount: selected.length,
      maximumSelected: CommunityHangarSharing.maximumTargets,
      explicit: value.usesExplicitTargets,
      allowImages: true,
    );
  }

  @override
  Future<OrganizationSharingPage> page(
    String editRef,
    String sourceRef,
    int offset,
  ) => throw const FormatException();
  @override
  Future<CommunityHangarSharingOutcome> save(
    String editRef,
    String? sourceRef,
    String? strategy,
    List<String> selectedRefs, {
    bool includeImages = false,
  }) => port.saveHangarSharing(
    editRef,
    selectedRefs,
    includeImages: includeImages,
  );
  @override
  Future<void> close() async {} // The existing community owner owns its port.
}
