/// A resource-only maintenance boundary, independent of account authorization.
/// Implementations retain excluded images, domain state and physical IO leases.
abstract interface class DownloadableImageCache {
  void beginImageMaintenance();
  void endImageMaintenance();
}

/// A presentation owner exposes only its resource participant, never sessions.
abstract interface class DownloadableImageOwner {
  DownloadableImageCache get downloadableImages;
}

/// Cross-engine retirement must be confirmed before maintenance is successful.
abstract interface class ImageCacheMaintenanceBarrier {
  Future<void> get imageMaintenanceSettled;
}
