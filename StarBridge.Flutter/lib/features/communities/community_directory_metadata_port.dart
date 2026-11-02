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

/// One authorized read, with optional decoration completion kept separate.
/// The page owner must recheck its account/read/image epochs before publishing
/// [images]. Neither stage supplies authorization for a later command.
final class CommunityDirectoryRead {
  const CommunityDirectoryRead(
    this.page, {
    this.images,
    this.progress,
    this.retireImages = _keepImages,
  });
  final CommunityDirectory page;
  final Future<CommunityDirectory>? images;

  /// Partial pages while [images] is pending, one per arrived logo, so a slow
  /// or failing tail never hides logos that already arrived (2026-10-20).
  final Stream<CommunityDirectory>? progress;

  /// Stop only future optional work. Already started physical reads still own
  /// their quota and report their real completion/error.
  final void Function() retireImages;
  static void _keepImages() {}
}

abstract interface class CommunityProgressiveDirectoryPort {
  Future<CommunityDirectoryRead> readDirectoryProgressively({
    required String view,
    required String query,
    String? after,
    String? filters,
  });
}
