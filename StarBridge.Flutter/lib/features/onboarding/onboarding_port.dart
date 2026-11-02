import 'onboarding_models.dart';

/// Existing domains retain ownership of log evidence, settings and consent.
/// An Adapter must validate source/account revisions again on every write.
/// read() is side-effect free. Saving UI progress must never grant permissions.
/// applyMode must acknowledge the requested mode; local mode requires confirmed
/// publication suspension, not just a label. Online mode grants no sharing.
/// onlineSetupPending acknowledges only the chosen setup route while the same
/// local owner remains active and publication suspended. finish must return an
/// actual installed online owner; pending setup cannot acknowledge completion.
abstract interface class OnboardingPort {
  /// Invalidates presentation only. The next read must return current revisions.
  Stream<void> get invalidations;
  Future<OnboardingReply> read();
  Future<OnboardingReply> execute(
    OnboardingAction action,
    OnboardingCheckpoint checkpoint,
  );
  Future<OnboardingReply> save(OnboardingCheckpoint checkpoint);
  Future<OnboardingReply> finish(OnboardingCheckpoint checkpoint);
}
