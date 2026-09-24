import 'sync_privacy_models.dart';
import 'sync_privacy_port.dart';

final class InMemorySyncPrivacyAdapter implements SyncPrivacyPort {
  InMemorySyncPrivacyAdapter({required SyncPrivacySnapshot initial})
    : _snapshot = initial;

  factory InMemorySyncPrivacyAdapter.forReview() => InMemorySyncPrivacyAdapter(
    initial: const SyncPrivacySnapshot.available(
      revision: 7,
      settings: SyncPrivacySettingsValue(
        realtimeSyncEnabled: true,
        hasActiveCollaboration: true,
        friendDefaults: FriendVisibilityDefaults.newAccount(),
        eventSharing: ActivityEventSharing(
          enabled: true,
          presence: true,
          server: true,
          ship: true,
          location: false,
          life: true,
        ),
        social: SocialPrivacySettings(
          allowFriendRequests: true,
          allowStrangerDirectMessages: true,
          recentlyPlayedDiscoverable: true,
          hideLowConfidenceLocation: true,
        ),
      ),
    ),
  );

  SyncPrivacySnapshot _snapshot;
  bool failNextUpdate = false;

  SyncPrivacySnapshot get current => _snapshot;

  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<SyncPrivacySnapshot> read() async => _snapshot;

  @override
  Future<SyncPrivacyWriteResult> update(
    SyncPrivacySettingsValue settings, {
    required int expectedRevision,
  }) async {
    if (failNextUpdate) {
      failNextUpdate = false;
      return const SyncPrivacyWriteResult.failed(
        SyncPrivacyFailure.writeFailed,
      );
    }
    final currentRevision = _snapshot.revision;
    if (_snapshot.availability != SyncPrivacyAvailability.available ||
        currentRevision == null ||
        currentRevision != expectedRevision) {
      return const SyncPrivacyWriteResult.failed(
        SyncPrivacyFailure.writeConflict,
      );
    }
    _snapshot = SyncPrivacySnapshot.available(
      settings: settings,
      revision: currentRevision + 1,
      allowEditing: _snapshot.allowEditing,
    );
    return SyncPrivacyWriteResult.completed(_snapshot);
  }

  @override
  Future<void> close() async {}
}
