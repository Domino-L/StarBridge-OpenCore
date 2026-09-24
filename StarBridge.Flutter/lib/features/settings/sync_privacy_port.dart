import 'sync_privacy_models.dart';

abstract interface class SyncPrivacyPort {
  Stream<void> get invalidations;

  Future<SyncPrivacySnapshot> read();

  Future<SyncPrivacyWriteResult> update(
    SyncPrivacySettingsValue settings, {
    required int expectedRevision,
  });

  Future<void> close();
}
