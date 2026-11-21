import 'community_directory_models.dart';

final class CommunityFailure implements Exception {
  const CommunityFailure(this.code);
  final String code;
}

abstract interface class CommunitiesPort {
  Stream<void> get invalidations;
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  });

  /// `accepted`, `rejected` or `unknown`; or a definite relay refusal the page
  /// explains instead: `identityRequired` (game identity not verified) or
  /// `identityAmbiguous` (a name in the organization maps to several accounts).
  Future<String> execute(String action, String targetRef);
  Future<void> close();
}

final class UnavailableCommunities implements CommunitiesPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async => throw const CommunityFailure('unavailable');
  @override
  Future<String> execute(String action, String targetRef) async => 'rejected';
  @override
  Future<void> close() async {}
}
