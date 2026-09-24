final class CommunityLogoSource {
  const CommunityLogoSource(
    this.sourceRef,
    this.previewImageData,
    this.width,
    this.height,
  );
  final String sourceRef, previewImageData;
  final int width, height;
}

abstract interface class CommunityLogoPort {
  bool get canPickLogo;
  Future<CommunityLogoSource?> pickLogo();
  Future<String> cropLogo(String sourceRef, double x, double y, double size);
  Future<void> clearLogo();
}
