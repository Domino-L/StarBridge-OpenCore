import 'local_privacy_settings.dart';

abstract interface class LocationConfidencePrivacyPort {
  bool get locationConfidenceSupported;
}

abstract interface class LocalPrivacyPort {
  Stream<void> get invalidations;
  Future<LocalPrivacySnapshot> read();
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings);
  Future<void> close();
}
