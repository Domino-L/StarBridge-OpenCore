import 'communities_module.dart';

/// The authorized directory without waiting for optional image downloads.
/// Consumers can hydrate deferred logos through CommunityWorkspacePort.
abstract interface class CommunityDirectoryMetadataPort {
  Future<CommunityDirectory> readDirectoryMetadata({
    required String view,
    required String query,
    String? after,
    String? filters,
  });
}
