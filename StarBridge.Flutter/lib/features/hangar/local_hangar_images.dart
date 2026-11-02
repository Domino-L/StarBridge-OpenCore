import '../communities/community_logo_port.dart';

abstract interface class LocalHangarImagePort implements CommunityLogoPort {
  Future<String?> readImage();
  Future<void> saveImage();
  Future<void> restoreImage();
}

abstract interface class LocalHangarImageProvider {
  LocalHangarImagePort? imageFor(String shipId, int revision);
}
