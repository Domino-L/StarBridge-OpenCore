import 'sync_privacy_models.dart';
import 'sync_privacy_port.dart';

final class HostUnavailableSyncPrivacyAdapter implements SyncPrivacyPort {
  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<SyncPrivacySnapshot> read() async =>
      const SyncPrivacySnapshot.unavailable();

  @override
  Future<SyncPrivacyWriteResult> update(
    SyncPrivacySettingsValue settings, {
    required int expectedRevision,
  }) async =>
      const SyncPrivacyWriteResult.failed(SyncPrivacyFailure.hostUnavailable);

  @override
  Future<void> close() async {}
}
