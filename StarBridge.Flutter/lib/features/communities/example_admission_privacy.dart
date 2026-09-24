import '../settings/local_privacy_port.dart';
import '../settings/local_privacy_settings.dart';

/// Example-session state. Leases never forward reads or writes to Native Host.
final class ExampleAdmissionPrivacy {
  LocalPrivacySnapshot _snapshot = const LocalPrivacySnapshot(revision: 0);

  LocalPrivacyPort open() => _ExampleAdmissionPrivacyLease(this);

  void reset() => _snapshot = const LocalPrivacySnapshot(revision: 0);
}

final class _ExampleAdmissionPrivacyLease implements LocalPrivacyPort {
  _ExampleAdmissionPrivacyLease(this.owner);
  final ExampleAdmissionPrivacy owner;
  bool closed = false;

  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<LocalPrivacySnapshot> read() async {
    if (closed) throw StateError('Closed example lease');
    return owner._snapshot;
  }

  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) async {
    if (closed) throw StateError('Closed example lease');
    return owner._snapshot = LocalPrivacySnapshot(
      revision: owner._snapshot.revision + 1,
      settings: settings,
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
