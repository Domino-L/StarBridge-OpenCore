import 'dart:async';

/// A reader for a currently authorized ship owner's avatar, using Host-issued
/// organization/member references. Account invalidation belongs to shipsPort.
typedef CommunityShipAvatarReader = Future<Map<String, Object?>> Function(
  String targetRef,
  String ownerMemberRef, {
  required int offset,
  String? version,
});

/// Omitted configuration keeps legacy community media. An explicit instance
/// without a reader denies media reads, even if the source also has workspace
/// media capabilities. No image/report authority is inferred from a URL.
final class CommunityShipAvatarAccess {
  const CommunityShipAvatarAccess({this.read});

  final CommunityShipAvatarReader? read;
}
