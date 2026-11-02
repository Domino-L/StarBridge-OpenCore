import 'community_logo_port.dart';

/// Fixed crop ratios; the Host enforces the same ratios and output sizes.
const communityWideImageAspect = <String, double>{
  'banner': 4,
  'background': 16 / 9,
};

/// Native picker for banner and background images. Flutter only sees a
/// bounded preview and an opaque reference, never a path.
abstract interface class CommunityWideImagePort {
  bool get canPickWideImage;
  Future<CommunityLogoSource?> pickWideImage(String kind);

  /// x/y use the original axes; width is a fraction of the original width.
  Future<String> cropWideImage(
    String sourceRef,
    String kind,
    double x,
    double y,
    double width,
  );
  Future<void> clearWideImage();
}
